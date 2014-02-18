logger = require("rufus").getLogger "configurator"
argv = require("minimist") process.argv.slice 2
Vk = require("./vk").Vk
readline = require "readline"
async = require "async"
fs = require "fs"

logger.debug "got arguments:", argv

interactive = process.stdout.isTTY or argv.interactive
interactive = false if argv.batch
logger.debug "running with %sinteractive console", if not interactive then "non-" else ""

getPropertyByPath = (obj, path) ->
  path = path.split('.')
  parent = obj

  if path.length > 1
    parent = parent[path[i]] for i in [0..path.length - 2]

  parent?[path[path.length - 1]]

setPropertyByPath = (obj, path, value) ->
  path = path.split('.')
  parent = obj

  if path.length > 1
    parent = (parent[path[i]] ||= {}) for i in [0..path.length - 2]

  parent[path[path.length - 1]] = value

makeCompleter = (completions) ->
    (line) ->
        hits = completions.filter (c) -> c.indexOf(line) is 0
        [(if hits.length then hits else completions), line]

askable =
    "vk.params.access_token":
        description: "Enter vk access token:"
        default: "none"
        completions: []
    "vk.params.lang":
        description: "Choose preferred language:"
        default: "en"
        completions: ["en", "ru", "be"]

askOption = (option, callback) ->
    logger.debug "creating readline to ask for", option
    rl = readline.createInterface
        completer: makeCompleter askable[option].completions
        input: process.stdin
        output: process.stdout
    question = "#{askable[option].description} (#{askable[option].default}) "
    rl.question question, (answer) ->
        do rl.close
        answer = answer or askable[option].default
        callback answer

checkConfig = (config, callback) ->
    (callback config; return) if argv["check-config"] is false
    vk = new Vk config.vk
    vk.callMethod "account.getAppPermissions", {}, (permissions) ->
        logger.warn "not enough permissions, check access token" unless permissions is config.vk.expectedPermissions
        vk.callMethod "users.get", {}, (users) ->
            config.vk.userName = "#{users[0].first_name} #{users[0].last_name}"
            config.vk.userId = users[0].id
            callback config

populateConfig = (config) ->
    for key, value of argv
        if (key.indexOf "dump-") is 0
            category = key.substr "dump-".length
            if value
                logger.debug "adding category", category
                config.dumpCategories.push category
            else
                logger.debug "removing category", category
                idx = config.dumpCategories.indexOf category
                config.dumpCategories.splice idx, 1 unless idx is -1
    config


module.exports.getConfig = (callback) ->
    try
        config = require "./config.json"
        config = populateConfig config
        checkConfig config, callback
    catch e
        logger.debug "no config found (%s), trying to find out", e
        process.exit 2 unless interactive
        config = require "./default-config.json"
        keys = (option for option of askable)
        async.eachSeries keys, ((key, done) ->
            askOption key, (answer) ->
                setPropertyByPath config, key, answer
                do done
        ), ->
            checkConfig config, ->
                fs.writeFileSync "config.json", JSON.stringify config, null, 4
                config = populateConfig config
                callback config
            