request = require "request"
async = require "async"
rufus = require "rufus"
logger = rufus.getLogger "dumper"
downloaderLogger = rufus.getLogger "dumper.downloader"
fs = require "fs"

normalizeFilename = (path) -> # TODO: better filter
    path = path.substring 100 if path.length > 100
    path = path.replace /[\\\/]/g, ""

downloadFile = (path, url, done) ->
    downloaderLogger.debug "starting download %s -> %s", url, path
    request(url).pipe(fs.createWriteStream path).on "finish", done

titleCase = (str) -> # TODO: improve regexp (:
    str.toLowerCase().replace /./, (match) -> do match.toUpperCase

class VkDumper
    constructor: (@vk, @config, @interactive) ->
        logger.debug "constructed with {interactive: %s}", @interactive
        @callVkMethod = async.memoize (=> @vk.callMethod.apply @vk, arguments), (method, params) ->
            "#{method} - #{JSON.stringify params}"

    dumpUser: (userId, path, done) ->
        logger.debug "dumping user %s", userId
        fs.mkdirSync path unless fs.existsSync path
        sexes = ["Of unknown sex", "Female", "Male"]
        @callVkMethod "users.get", {user_ids: userId, fields: @vk.userFields}, (data) ->
            user = data[0]
            fs.writeFileSync "#{path}/info.md",
                """
                #{user.first_name} #{user.last_name} - #{user.id}
                #{(user.first_name + " " + user.last_name + " - " + user.id).replace /./g, "="}

                #{sexes[user.sex]}, born on #{user.bdate or "01.01.1970"}, https://vk.com/#{user.domain}
                Specified #{user.site or "none :("} as his own site

                Too lazy to parse those:
                #{JSON.stringify user, null, 4}
                """
            downloadFile "#{path}/avatar.jpg", user.photo_max_orig, done

    dumpMessageContent: (params, path, done) ->
        dialog = fs.createWriteStream "#{path}/history.md"
        @vk.gatherArraySeries "messages.getHistory", params, ((count, message, doneMessage) =>
            @callVkMethod "users.get", {user_id: message.user_id}, (data) =>
                user = data[0]
                userName = "#{user.first_name} #{user.last_name}"
                userName = "all" if userName is @config.vk.userName
                flow = if message.out is 1 then "#{@config.vk.userName} -> #{userName}" else "#{userName} -> #{@config.vk.userName}"
                msg = """
                      --------------------------------------------
                      #{new Date message.date * 1000}: #{flow}, #{if message.read_state then "read" else "unread"}
                      #{message.title or ""}

                      #{message.body}

                      """
                dialog.write msg, doneMessage
        ), (-> do dialog.end; do done)

    dumpChat: (dialog, path, done) ->
        logger.debug "dumping chat", dialog.chat_id
        dir = "#{path}/#{dialog.chat_id} - chat - #{dialog.title}"
        fs.mkdirSync dir
        @dumpMessageContent {chat_id: dialog.chat_id}, dir, done
    dumpDialog: (dialog, path, done) ->
        logger.debug "dumping dialog for user", dialog.user_id
        @callVkMethod "users.get", {user_id: dialog.user_id}, (data) =>
            user = data[0]
            title = "#{user.first_name} #{user.last_name}"
            title = title.replace /[^\w\-. ]/g, ""
            dir = "#{path}/#{user.id} - dialog - #{title}"
            fs.mkdirSync dir
            @dumpMessageContent {user_id: user.id}, dir, done

    dumpMessages: (path, done) ->
        logger.debug "dumping all messages"
        fs.mkdirSync path unless fs.existsSync path
        @vk.gatherArraySeries "messages.getDialogs", {}, ((count, dialog, doneDialog) =>
            if dialog.chat_id?
                @dumpChat dialog, path, doneDialog
            else
                @dumpDialog dialog, path, doneDialog
        ), done

    dumpAlbum: (album, path, done) ->
        fs.mkdirSync path unless fs.existsSync path
        @vk.gatherArraySeries "photos.get", {count: 1000, album_id: album.id}, ((count, photo, donePhoto) =>
            photoUrl = photo.photo_2560 || photo.photo_1280 || photo.photo_807 || photo.photo_604 || photo.photo_75
            downloadFile "#{path}/#{photo.id}.jpg", photoUrl, donePhoto
        ), done
    dumpPhotos: (path, done) ->
        logger.debug "dumping all photo albums"
        fs.mkdirSync path unless fs.existsSync path
        @vk.gatherArraySeries "photos.getAlbums", {owner_id: @config.vk.userId, need_system: 1}, ((count, album, doneAlbum) =>
            @dumpAlbum album, "#{path}/#{album.title}", doneAlbum
        ), done

    dumpVideos: (path, done) ->
        logger.debug "dumping all videos"
        fs.mkdirSync path unless fs.existsSync path
        logger.warn "videos downloading is not implemented yet"
        fs.writeFile "#{path}/notice.md", "nothing here currently", done

    dumpSong: (song, path, done) ->
        song.title = normalizeFilename song.title
        downloadFile "#{path}/#{song.artist} - #{song.title}.mp3", song.url, done
    dumpAudios: (path, done) ->
        logger.debug "dumping all audio records"
        fs.mkdirSync path unless fs.existsSync path
        @vk.gatherArraySeries "audio.get", {count: 1000, owner_id: @config.vk.userId}, ((count, song, doneSong) =>
            @dumpSong song, path, doneSong
        ), done

    dumpFriends: (path, done) ->
        logger.debug "dumping all the friends"
        fs.mkdirSync path unless fs.existsSync path
        @vk.gatherArraySeries "friends.get", {count: 1000, fields: "first_name,last_name"}, ((count, friend, doneFriend) =>
            dir = "#{path}/#{friend.first_name} #{friend.last_name}"
            @dumpUser friend.id, dir, doneFriend
        ), done

    dumpSelf: (path, done) ->
        @dumpUser @vk.config.userId, path, done

    backupDataDir: (path, backupTo) ->
        fs.mkdirSync backupTo unless fs.existsSync backupTo
        fs.renameSync path, "#{backupTo}/#{path}-#{do Date.now}"

    dumpEverything: (path, done) ->
        @backupDataDir path, "backups" if fs.existsSync path

        fs.mkdirSync path
        async.eachSeries @config.dumpCategories, ((category, dumpDone) =>
            @["dump#{titleCase category}"] "#{path}/#{category}", dumpDone
        ), done

module.exports.VkDumper = VkDumper