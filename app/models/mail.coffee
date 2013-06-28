fs = require 'fs'
async = require 'async'
MailGetter = require '../../lib/mail_getter'

module.exports = (compound, Mail) ->
    {Attachment} = compound.models

    Mail.fromMailbox = (params, callback) ->
        Mail.request "byMailbox", params, callback

    Mail.dateId = (params, callback) ->
        Mail.request "dateId", params, callback

    Mail.fromMailboxByDate = (params, callback) ->
        Mail.request "dateByMailbox", params, callback

    # Get attachments returned by mailparser as parameter.
    # Save them as couchdb attachments.
    Mail::saveAttachments = (attachments, callback) ->

        return callback null unless attachments? and attachments.length > 0

        async.each attachments, (attachment, callback) =>
            params =
                cid:         attachment.contentId
                fileName:    attachment.fileName
                contentType: attachment.contentType
                length:      attachment.length
                checksum:    attachment.checksum
                mailbox:     @mailbox
                mailId:      @id

            fileName =  "/tmp/#{attachment.fileName}"
            fs.writeFile fileName, attachment.content, (error) =>
                return callback error if error
                @attachFile fileName, params, (error) =>
                    fs.unlink fileName, (err) =>
                        callback(error or err)

        , (err) =>
            console.log err
            callback err

    Mail::updateAndSync = (attributes, callback) ->

        needSync = @changedFlags attributes.flags

        @updateAttributes attributes, (err) =>
            return callback err if err

            if needSync then @sync callback
            else callback null

    Mail::changedFlags = (newflags) ->
        oldseen    = '\\Seen'    in @flags
        oldflagged = '\\Flagged' in @flags

        newseen    = '\\Seen'    in newflags
        newflagged = '\\Flagged' in newflags

        oldseen isnt newseen or oldflagged isnt newflagged

    # Update mail attributes with given flags. Save model if changes occured.
    Mail::updateFlags = (flags, callback=->) ->
        if @changedFlags flags
            @updateAttributes flags: flags, callback
        else
            callback null

    Mail::toString = (callback) ->
        "mail: #{@mailbox} #{@id}"
