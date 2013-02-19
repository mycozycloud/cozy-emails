###
    @file: mailbox.coffee
    @author: Mikolaj Pawlikowski (mikolaj@pawlikowski.pl/seeker89@github)
    @description: 
        The model used to wrap tasks on other servers:
            * fetching mails with node-imap,
            * parsing mail with nodeparser,
            * saving mail to the database,
            * sending mail with nodemailer,
            * flagging mail on remote servers (not yet implemented)
###

nodemailer = require "nodemailer"
imap = require "imap"
mailparser = require "mailparser"


# helpers

getDateSent = (mailParsedObject) ->
    # choose the right date
    if mailParsedObject.headers.date
        if mailParsedObject.headers.date instanceof Array
            # if an array pick the first date
            dateSent = new Date mailParsedObject.headers.date[0]
        else
            # else take the whole thing
            dateSent = new Date mailParsedObject.headers.date
    else
        dateSent = new Date()

# Just to be able to recognise the mailbox in the console
Mailbox::toString = ->
    "[Mailbox " + @name + " #" + @id + "]"

Mailbox::fetchFinished = (callback) ->
    @updateAttributes IMAP_last_fetched_date: new Date(), (error) =>
        if error
            callback error
        else
            LogMessage.createNewMailInfo @, callback
            
Mailbox::fetchFailed = (callback) ->
    data =
        status: "Mail check failed."

    @updateAttributes data, (error) =>
        if error
            callback error
        else
            LogMessage.createCheckMailError @, callback

Mailbox::importError = (callback) ->
    data =
        imported: false
        status: "Could not prepare the import."

    @updateAttributes data, (error) =>
        if error
            callback error
        else
            LogMessage.createImportPreparationError @, callaback

Mailbox::importSuccessfull = (callback) ->
    data =
        imported: true
        status: "Import successful !"

    @updateAttributes data, (error) =>
        if error
            callback error
        else
            LogMessage.createImportSuccess @, callback

Mailbox::importFailed = (callback) ->
    data =
        imported: false
        importing: false
        activated: false

    @updateAttributes data, (error) =>
        if error
            callback error
        else
            LogMessage.createBoxImportError @

Mailbox::progress = (progress, callback) ->
    data =
        status: "Import #{progress} %"

    @updateAttributes data, (error) =>
        LogMessage.createImportProgressInfo @, progress, callback


Mailbox::markError = (error, callback) ->
    data =
        status: error.toString()

    mailbox.updateAttributes data, (err) ->
        if err
            callback err
        else
            LogMessage.createImportError error, callback
    
###
    Generic function to send mails, using nodemailer
###
Mailbox::sendMail = (data, callback) ->
    
    # create the connection - transport object, 
    # and configure it with our mialbox's data
    transport = nodemailer.createTransport "SMTP",
        host: @SMTP_server
        secureConnection: @SMTP_ssl
        port: @SMTP_port
        auth:
            user: @login
            pass: @pass

    # configure the message object to send
    message =
        from: @SMTP_send_as
        to: data.to
        cc: data.cc if data.cc?
        bcc: data.bcc if data.bcc?
        subject: data.subject
        headers: data.headers if data.headers?
        html: data.html
        generateTextFromHTML: true
        
    console.log "Sending Mail"
    transport.sendMail message, (error) ->
        if error
            console.error "Error occured"
            console.error error.message
            callback error
        else
            console.log "Message sent successfully!"
            callback()

    transport.close()


###
    ## Fetching new mail from server
    
    # @job - kue job
    # @callback - success callback
    # @limit - how many new messages we want to download at max

###

Mailbox::connectImapServer = (callback) ->

    # let's create a connection
    server = new imap.ImapConnection
        username: @login
        password: @pass
        host: @IMAP_server
        port: @IMAP_port
        secure: @IMAP_secure

    # set up lsiteners, handle errors and callback
    server.on "alert", (alert) ->
        console.log "[SERVER ALERT] #{alert}"

    server.on "error", (error) ->
        console.error "[ERROR]: #{error.toString()}"
        mailbox.updateAttributes status: error.toString(), (err) ->
            console.error "Mailbox update with error status"
            callback error

    server.on "close", (error) ->
        console.log "Connection closed (error: #{error.toString()})"
     
    server.connect (err) =>
        callback err, server
             
Mailbox::loadInbox = (server, callback) ->
    console.log "Connection established successfuly"
    server.openBox 'INBOX', false, (err, box) ->
        console.log "INBOX opened successfuly"
        callback err, server
 
Mailbox::fetchMessage = (server, mailToBe, callback) ->
    
    fetch = server.fetch mailToBe.remoteId,
        request:
            body: 'full'
            headers: false

    messageFlags = []
    fetch.on 'message', (message) =>
                
        parser = new mailparser.MailParser()

        parser.on "end", (mailParsedObject) =>
            dateSent = getDateSent mailParsedObject
            attachments = mailParsedObject.attachments
            mail =
                mailbox: @id
                date: dateSent.toJSON()
                dateValueOf: dateSent.valueOf()
                createdAt: new Date().valueOf()
                from: JSON.stringify mailParsedObject.from
                to: JSON.stringify mailParsedObject.to
                cc: JSON.stringify mailParsedObject.cc
                subject: mailParsedObject.subject
                priority: mailParsedObject.priority
                text: mailParsedObject.text
                html: mailParsedObject.html
                id_remote_mailbox: mailToBe.remoteId
                headers_raw: JSON.stringify mailParsedObject.headers
                references: mailParsedObject.references or ""
                inReplyTo: mailParsedObject.inReplyTo or ""
                flags: JSON.stringify messageFlags
                read: "\\Seen" in messageFlags
                flagged: "\\Flagged" in messageFlags
                hasAttachments: if mailParsedObject.attachments then true else false
            
            Mail.create mail, (err, mail) ->
                if err
                    callback err
                else
                    msg = "New mail created: #{mail.id_remote_mailbox}"
                    msg += " #{mail.id} [#{mail.subject}] "
                    msg += JSON.stringify mail.from
                    console.log msg
                    
                    mail.saveAttachments attachments, (err) ->
                        return callback(err) if err
                        mailToBe.destroy (error) ->
                            return callback(err) if err
                            callback null

        message.on "data", (data) ->
            # on data, we feed the parser
            parser.write data.toString()

        message.on "end", ->
            # additional data to store, which is "forgotten" byt the parser
            # well, for now, we will store it on the parser itself
            messageFlags = message.flags
            do parser.end
     
            fetch.on 'error', (error) ->
                server.logout () ->
                    console.log 'Error emitted on fetch object'
                    console.log error
                    server.emit 'error', error


Mailbox::getNewMail = (job, callback, limit=250)->
    
    ## dependences
    imap = require "imap"
    mailparser = require "mailparser"

    # global vars
    debug = true
    
    # reload
    @reload (error, mailbox) ->
        
        if error
            callback error
        else
            id = Number(mailbox.IMAP_last_fetched_id) + 1
            console.log "Fetching mail " + mailbox + " | UID " + id + ':' + (id + limit) if debug
    
            # let's create a connection
            server = new imap.ImapConnection
                username: mailbox.login
                password: mailbox.pass
                host: mailbox.IMAP_server
                port: mailbox.IMAP_port
                secure: mailbox.IMAP_secure

            # set up listeners, handle errors and callback
            server.on "alert", (alert) ->
                console.log "[SERVER ALERT]" + alert

            server.on "error", (error) ->
                console.error "[ERROR]: " + error.toString()
                mailbox.updateAttributes {status: error.toString()}, (err) ->
                    console.error "Mailbox update with error status"
                    callback error

            server.on "close", (error) ->
                console.log "Connection closed: " + error.toString() if debug
                
            emitOnErr = (err) ->
                if err
                    server.emit "error", err

            # LET THE GAMES BEGIN
            server.connect (err) =>

                emitOnErr err
                unless err
        
                    console.log "Connection established successfuly" if debug

                    server.openBox 'INBOX', false, (err, box) ->

                        emitOnErr err
                        unless err
                
                            console.log "INBOX opened successfuly" if debug
                            
                            # search mails on server satisfying constraints
                            server.search [['UID', id + ':' + (id + limit)]], (err, results) =>

                                emitOnErr err
                                unless err

                                    console.log "Search query successful" if debug
                            
                                    # nothing to download
                                    unless results.length
                                        console.log "Nothing to download" if debug
                                        server.logout () ->
                                            callback()
                                    else
                                        console.log "[" + results.length + "] mails to download" if debug
                                        LogMessage.createImportInfo results, mailbox

                                        mailsToGo = results.length
                                        mailsDone = 0
                                
                                        # for every ID, fetch the message
                                        # closure, to avoid sharing variables
                                        fetchOne = (i) ->
                                    
                                            console.log "fetching one: " + i + "/" + results.length if debug
                                    
                                            if i < results.length
                                        
                                                remoteId = results[i]
                                    
                                                messageFlags = []
                        
                                                fetch = server.fetch remoteId,
                                                    request:
                                                        body: "full"
                                                        headers: false

                                                console.log "let's go fetching"
                                                
                                                fetch.on "message", (message) ->
                                                    parser = new mailparser.MailParser()
                                                    
                                                    parser.on "end", (mailParsedObject) ->
                                                
                                                        # choose the right date
                                                        if mailParsedObject.headers.date
                                                            if mailParsedObject.headers.date.toString() == '[object Array]'
                                                                # if an array pick the first date
                                                                dateSent = new Date mailParsedObject.headers.date[0]
                                                            else
                                                                dateSent = new Date mailParsedObject.headers.date
                                                        else
                                                            dateSent = new Date()
                                                
                                                        # compile the mail data
                                                        mail =
                                                            mailbox:            mailbox.id
                                                            date:                 dateSent.toJSON()
                                                            dateValueOf:    dateSent.valueOf()
                                                            createdAt:        new Date().valueOf()
                                                            from:                 JSON.stringify mailParsedObject.from
                                                            to:                     JSON.stringify mailParsedObject.to
                                                            cc:                     JSON.stringify mailParsedObject.cc
                                                            subject:            mailParsedObject.subject
                                                            priority:         mailParsedObject.priority
                                                            text:                 mailParsedObject.text
                                                            html:                 mailParsedObject.html
                                                            id_remote_mailbox: remoteId
                                                            headers_raw:    JSON.stringify mailParsedObject.headers
                                                    
                                                            # optional parameters
                                                            references:     mailParsedObject.references or ""
                                                            inReplyTo:        mailParsedObject.inReplyTo or ""
                    
                                                            # flags
                                                            flags:                JSON.stringify messageFlags
                                                            read:                 "\\Seen" in messageFlags
                                                            flagged:            "\\Flagged" in messageFlags
                                                            hasAttachments: if mailParsedObject.attachments then true else false
                                                    
                                                        attachments = mailParsedObject.attachments

                                                        # and now we can create a new mail on database, as a child of this mailbox
                                                        Mail.create mail, (err, mail) ->
        
                                                            # for now we will just skip messages which are being rejected by parser
                                                            # emitOnErr err
                                                            unless err
                                                            
                                                                # attachements
                                                                mail.saveAttachments attachments, ->

                                                                        mailbox.reload (error, mailbox) ->
                                                                    
                                                                            if error
                                                                                server.logout () ->
                                                                                    console.log "Error emitted on mailbox.reload: " + error.toString() if debug
                                                                                    server.emit "error", error
                                                                            else
                                                                        
                                                                                # check if we need to update the last_fetch_id index in the mailbox
                                                                                if mailbox.IMAP_last_fetched_id < mail.id_remote_mailbox
                                                                            
                                                                                    mailbox.updateAttributes {IMAP_last_fetched_id: mail.id_remote_mailbox}, (error) ->
                                                                                
                                                                                        if error
                                                                                            server.logout () ->
                                                                                                console.log "Error emitted on mailbox.update: " + error.toString() if debug
                                                                                                server.emit "error", error
                                                                                        else
                                                                                            console.log "New highest id saved to mailbox: " + mail.id_remote_mailbox if debug
                                                                                            mailsDone++
                                                                                            job.progress mailsDone, mailsToGo
                                                                                            # next iteration of our asynchronous for loop
                                                                                            fetchOne(i + 1)
                                                                                            # when finished
                                                                                            if mailsToGo == mailsDone
                                                                                                callback()
                                                                                else
                                                                                    mailsDone++
                                                                                    job.progress mailsDone, mailsToGo
                                                                                    # next iteration of our asynchronous for loop
                                                                                    fetchOne(i + 1)
                                                                                    # when finished
                                                                                    if mailsToGo == mailsDone
                                                                                        callback()
                                                            else
                                                                console.error "Parser error - skipping this message for now: " + err.toString()
                                                                fetchOne(i + 1)

                                                    message.on "data", (data) ->
                                                        # on data, we feed the parser
                                                        parser.write data.toString()

                                                    message.on "end", ->
                                                        # additional data to store, which is "forgotten" byt the parser
                                                        # well, for now, we will store it on the parser itself
                                                        messageFlags = message.flags
                                                        do parser.end
                                                                    
                                                fetch.on "error", (error) ->
                                                    # undocumented error emitted on fetch() object
                                                    server.logout () ->
                                                        console.log "Error emitted on fetch object: " + error.toString() if debug
                                                        server.emit "error", error

                                            else
                                                # my job here is done
                                                server.logout () ->
                                                    if mailsToGo != mailsDone
                                                        server.emit "error", new Error("Could not import all the mail. Retry")
                                        # start the loop
                                        fetchOne(0)

###
    ## Specialised function to prepare a new mailbox for import and fetching new mail
###

Mailbox::setupImport = (callback) ->
    
    ## dependences
    imap = require "imap"

    # global vars
    mailbox = @
    debug = true
               
    emitOnErr = (server, error) ->
        if error
            console.log error
            server.emit "error", error

    loadInboxMails = (server) ->
        console.log "INBOX opened successfuly" if debug
        server.search ['ALL'], (err, results) =>
            if err
                emitOnErr err
            else
                console.log "Search query succeeded" if debug

                unless results.length
                    console.log "Nothing to download" if debug
                    server.logout()
                    callback()
                else
                    if debug
                        console.log "[" + results.length + "] mails to download"
                    
                    mailsToGo = results.length
                    mailsDone = 0
                    maxId = 0
                    fetchOne server, results, 0, mailsDone, mailsToGo, maxId

            
    # for every ID, fetch the message
    fetchOne = (server, results, i, mailsDone, mailsToGo, maxId) ->
        
        if i < results.length
            
            id = results[i]
        
            # find the biggest ID
            idInt = parseInt id
            maxId = idInt if idInt > maxId
    
            mailbox.mailsToBe.create remoteId: idInt, (error, mailToBe) ->
                if error
                    server.logout () -> server.emit "error", error
                else
                    console.log "#{mailToBe.remoteId} id saved successfully"
                    mailsDone++
        
                    # synchronise - all ids saved to the db
                    if mailsDone is mailsToGo
                        console.log "Finished saving ids to database"
                        console.log "max id = #{maxId}"
                        data =
                            mailsToImport: results.length
                            IMAP_last_fetched_id: maxId
                            activated: true
                            importing: true

                        mailbox.updateAttributes data, (err) ->
                            server.logout () ->
                                callback err
                    else
                        fetchOne server, results, i + 1, mailsDone, mailsToGo, maxId
        else
            # synchronise - all ids saved to the db
            if mailsDone isnt mailsToGo
                server.logout ->
                    msg =  "Error occured - not all ids could be stored to the database"
                    server.emit "error", new Error msg

    @connectImapServer (err, server) =>
        if err
            emitOnErr server, err
        else
            @loadInbox server, (err) ->
                if err
                    emitOnErr err
                else
                    loadInboxMails server

    

###
    ## Specialised function to get as much mails as possible from ids stored 
    # previously in the database
###

Mailbox::doImport = (job, callback) ->

    debug = true
    mailbox = @

    emitOnErr = (server, error) ->
        if error
            server.logout () ->
                console.log error
                server.emit "error", error
  
    @connectImapServer (err, server) =>
        if err
            emitOnErr server, err
        else
            MailToBe.fromMailbox mailbox, (err, mailsToBe) =>
                if err
                    emitOnErr err
                else if not mailsToBe.length
                    console.log 'Nothing to download'
                    server.logout()
                    callback()
                else
                    @loadInbox server, =>
                        loadInboxMails server, mailsToBe
                           
    loadInboxMails = (server, mailsToBe) =>
        mailsToGo = mailsToBe.length
        mailsDone = 0
        fetchOne server, mailsToBe, 0, mailsToGo, mailsDone
        
    fetchOne = (server, mailsToBe, i, mailsToGo, mailsDone) =>
        console.log "fetching one: #{i}/#{mailsToBe.length}"
        
        if i < mailsToBe.length
            
            mailToBe = mailsToBe[i]
            messageFlags = []

            @fetchMessage server, mailToBe, (err) =>
                if err
                    console.log 'Mail creation error, skip this message'
                    console.log err
                    fetchOne server, mailsToBe, i + 1, mailsToGo, mailsDone
                else
                    mailsDone++
                    diff = mailsToGo - mailsDone
                    importProgress = mailbox.mailsToImport - diff
                    job.progress importProgress, mailbox.mailsToImport
                    
                    if mailsToGo is mailsDone
                        callback()
                    else
                        fetchOne server, mailsToBe, i + 1, mailsToGo, mailsDone
                                       
        else
            server.logout () ->
                if mailsToGo isnt mailsDone
                    msg = 'Could not import all the mail.'
                    server.emit 'error', new Error msg
                callback()
