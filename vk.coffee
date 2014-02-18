EventEmitter = require("events").EventEmitter
RateLimiter = require("limiter").RateLimiter
logger = require("rufus").getLogger "vk"
request = require "request"
async = require "async"
merge = require "merge"

maxCountParameter = 200
userFields = "sex,bdate,city,country,photo_50,photo_100,photo_200_orig,photo_200,photo_400_orig,photo_max,photo_max_orig,online,online_mobile,lists,domain,has_mobile,contacts,connections,site,education,universities,schools,can_post,can_see_all_posts,can_see_audio,can_write_private_message,status,last_seen,common_count,relation,relatives,counters"

class Vk
    constructor: (@config) ->
        logger.debug "constructed with", @config
        @limiter = new RateLimiter @config.apiCallRateLimit.count, @config.apiCallRateLimit.time
        @userFields = userFields
        # @getPermissions (data) =>
        #   logger.info "Checking app permissions:", data
        #   if data is not @config.expectedPermissions
        #       logger.error "Check your token, there seems to be insufficient permissions"

    prepareUrl: (method, params) ->
        params = merge params, @config.params
        url = @config.baseUrl + method + "?" + ("&#{key}=#{value}" for key, value of params).join ''
        url = url.replace /\?\&/, "?" # to get prettier url
        logger.debug "got url to request", url
        url

    wrapCallback: (callback) ->
        (error, response, body) ->
            throw new Error error if error
            throw new Error "not ok" unless response.statusCode is 200
            data = JSON.parse body
            throw new Error data.error.error_msg if data.error?
            callback data.response
    callMethod: (method, params, callback) ->
        @limiter.removeTokens 1, =>
            request (@prepareUrl method, params), @wrapCallback callback

    gatherArray: (method, params, callback) ->
        result = []
        gather = =>
            params.count = params.count or maxCountParameter
            params.offset = result.length
            @callMethod method, params, (data) =>
                result = result.concat data.items
                if result.length < data.count then do gather else callback result
        do gather
    gatherArrayAsync: (method, params, callback, done = ->) ->
        gotChunks = 0
        gather = =>
            params.count = params.count or maxCountParameter
            params.offset = gotChunks
            @callMethod method, params, (data) =>
                gotChunks += data.items.length
                callback data.count, data.items, =>
                    if gotChunks < data.count then do gather else do done
        do gather
    gatherArraySeries: (method, params, callback, done = ->) ->
        @gatherArrayAsync method, params, ((count, items, doneItems) =>
            async.eachSeries items, ((item, doneItem) => callback count, item, doneItem), doneItems
        ), done

module.exports.Vk = Vk