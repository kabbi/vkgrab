# Some useful libs
VkDumper = require("./dumper").VkDumper
Vk = require("./vk").Vk
# Logging here
rufus = require "rufus"
logger = rufus.getLogger "index"
do rufus.console

require("./configurator").getConfig (config) ->
    rufus.config config.logs
    logger.info "Starting"
    vk = new Vk config.vk
    dumper = new VkDumper vk, config, true
    dumper.dumpEverything "data", ->
        logger.info "All done"