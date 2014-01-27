// Generated by CoffeeScript 1.6.3
var ImapConnection, MailGetter, MailParser,
  __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
  __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

ImapConnection = require("imap");

MailParser = require("mailparser").MailParser;

MailGetter = (function() {
  var SPECIALUSEFOLDERS;

  SPECIALUSEFOLDERS = ['INBOX', 'SENT', 'TRASH', 'DRAFTS', 'IMPORTANT', 'SPAM', 'STARRED', 'ALLMAIL', 'ALL'];

  function MailGetter(mailbox, password) {
    this.mailbox = mailbox;
    this.password = password;
    this.fetchMail = __bind(this.fetchMail, this);
    this.getMails = __bind(this.getMails, this);
    this.getAllMails = __bind(this.getAllMails, this);
    this.logout = __bind(this.logout, this);
    this.closeBox = __bind(this.closeBox, this);
    this.openBox = __bind(this.openBox, this);
    this.listFolders = __bind(this.listFolders, this);
  }

  MailGetter.prototype.connect = function(callback) {
    var _this = this;
    this.server = new ImapConnection({
      user: this.mailbox.login,
      password: this.password,
      host: this.mailbox.imapServer,
      port: this.mailbox.imapPort,
      secure: this.mailbox.imapSecure
    });
    this.server.on("alert", function(alert) {
      return _this.mailbox.log("[SERVER ALERT] " + alert);
    });
    this.server.on("error", function(err) {
      _this.mailbox.log("[ERROR]: " + (err.toString()));
      return _this.mailbox.updateAttributes({
        status: err.toString()
      }, function() {
        return LogMessage.createBoxImportError(function() {
          return callback(err);
        });
      });
    });
    this.server.on("close", function(err) {
      if (err) {
        return _this.mailbox.log("Connection closed (error: " + (err.toString()) + ")");
      } else {
        return _this.mailbox.log("Server connection closed.");
      }
    });
    this.mailbox.log("Try to connect...");
    return this.server.connect(function(err) {
      console.log(err);
      _this.mailbox.log('ready!');
      if (_this.mailbox.imapServer != null) {
        if (err) {
          _this.mailbox.log("Connection failed");
          return callback(err);
        } else {
          _this.mailbox.log("Connection established successfully");
          return callback(null);
        }
      } else {
        _this.mailbox.log('No host defined');
        return callback(new Error('No host defined'));
      }
    });
  };

  MailGetter.prototype.listFolders = function(callback) {
    var _this = this;
    return this.server.getBoxes(function(err, boxes) {
      var folders;
      folders = [];
      _this.flattenBoxesIntoFolders('', boxes, folders);
      return callback(null, folders);
    });
  };

  MailGetter.prototype.flattenBoxesIntoFolders = function(parentpath, obj, folders) {
    var childpath, key, path, specialType, type, value, _i, _len, _results;
    _results = [];
    for (key in obj) {
      value = obj[key];
      path = parentpath + key;
      if (__indexOf.call(value.attribs, 'NOSELECT') < 0) {
        type = null;
        for (_i = 0, _len = SPECIALUSEFOLDERS.length; _i < _len; _i++) {
          specialType = SPECIALUSEFOLDERS[_i];
          if (__indexOf.call(value.attribs, specialType) >= 0) {
            type = specialType;
          }
        }
        folders.push({
          name: key,
          path: path,
          specialType: type,
          attribs: value.attribs
        });
      }
      if (value.children) {
        childpath = path + value.delimiter;
        _results.push(this.flattenBoxesIntoFolders(childpath, value.children, folders));
      } else {
        _results.push(void 0);
      }
    }
    return _results;
  };

  MailGetter.prototype.openBox = function(folder, callback) {
    var _this = this;
    return this.server.openBox(folder, false, function(err, box) {
      return callback(err, _this.server);
    });
  };

  MailGetter.prototype.closeBox = function(callback) {
    this.mailbox.log("closing box");
    return this.server.closeBox(callback);
  };

  MailGetter.prototype.logout = function(callback) {
    this.mailbox.log("logging out");
    return this.server.logout(callback);
  };

  MailGetter.prototype.getAllMails = function(callback) {
    return this.server.search(['ALL'], callback);
  };

  MailGetter.prototype.getMails = function(range, callback) {
    return this.server.search([['UID', range]], callback);
  };

  MailGetter.prototype.fetchMail = function(remoteId, callback) {
    var fetch, mail,
      _this = this;
    mail = null;
    return fetch = this.server.fetch(remoteId, {
      body: true,
      headers: {
        parse: false
      },
      cb: function(fetch) {
        var messageFlags;
        messageFlags = [];
        return fetch.on('message', function(message) {
          var parser;
          parser = new MailParser();
          parser.on("end", function(mailParsed) {
            var attachments, dateSent, hasAttachments;
            dateSent = _this.getDateSent(mailParsed);
            attachments = mailParsed.attachments;
            hasAttachments = !!attachments;
            mail = {
              mailbox: _this.mailbox.id,
              date: dateSent.toJSON(),
              dateValueOf: dateSent.valueOf(),
              createdAt: new Date().valueOf(),
              from: JSON.stringify(mailParsed.from),
              to: JSON.stringify(mailParsed.to),
              cc: JSON.stringify(mailParsed.cc),
              subject: mailParsed.subject,
              priority: mailParsed.priority,
              text: mailParsed.text,
              html: mailParsed.html,
              idRemoteMailbox: new String(remoteId),
              remoteUID: remoteId,
              headersRaw: JSON.stringify(mailParsed.headers),
              references: mailParsed.references || "",
              inReplyTo: mailParsed.inReplyTo || "",
              flags: JSON.stringify(messageFlags),
              read: __indexOf.call(messageFlags, "\\Seen") >= 0,
              flagged: __indexOf.call(messageFlags, "\\Flagged") >= 0,
              hasAttachments: hasAttachments
            };
            return callback(null, mail, attachments);
          });
          message.on("data", function(data) {
            return parser.write(data.toString());
          });
          return message.on("end", function() {
            messageFlags = message.flags;
            return parser.end();
          });
        });
      }
    });
  };

  MailGetter.prototype.getDateSent = function(mailParsedObject) {
    var dateSent;
    if (mailParsedObject.headers.date) {
      if (mailParsedObject.headers.date instanceof Array) {
        return dateSent = new Date(mailParsedObject.headers.date[0]);
      } else {
        return dateSent = new Date(mailParsedObject.headers.date);
      }
    } else {
      return dateSent = new Date();
    }
  };

  MailGetter.prototype.getLastFlags = function(folder, limit, callback) {
    var start;
    start = folder.imapLastFetchedId - limit;
    if (start < 1) {
      start = 1;
    }
    if (start > folder.imapLastFetchedId) {
      return callback(null, {});
    }
    return this.getFlags("" + start + ":" + folder.imapLastFetchedId, callback);
  };

  MailGetter.prototype.getAllFlags = function(callback) {
    return this.getFlags("1:" + this.folder.imapLastFetchedId, callback);
  };

  MailGetter.prototype.getFlags = function(range, callback) {
    var flagDict,
      _this = this;
    flagDict = {};
    this.mailbox.log("fetch last modification started.");
    this.mailbox.log(range);
    return this.server.fetch(range, {
      cb: function(fetch) {
        return fetch.on('message', function(msg) {
          return msg.on('end', function() {
            return flagDict[msg.uid] = msg.flags;
          });
        });
      }
    }, function(err) {
      _this.mailbox.log("fetch modification finished.");
      return callback(err, flagDict);
    });
  };

  MailGetter.prototype.setFlags = function(mail, newflags, callback) {
    var _this = this;
    return this.getFlags(mail.remoteUID, function(err, dict) {
      var flag, oldflags, toAdd, toDel, _i, _j, _len, _len1;
      if (err) {
        return callback(err);
      }
      console.log(dict);
      oldflags = dict[mail.remoteUID];
      console.log(newflags, oldflags);
      toAdd = [];
      toDel = [];
      for (_i = 0, _len = oldflags.length; _i < _len; _i++) {
        flag = oldflags[_i];
        if (__indexOf.call(newflags, flag) < 0) {
          toDel.push(flag);
        }
      }
      for (_j = 0, _len1 = newflags.length; _j < _len1; _j++) {
        flag = newflags[_j];
        if (__indexOf.call(oldflags, flag) < 0) {
          toAdd.push(flag);
        }
      }
      console.log(toAdd, toDel);
      return _this.delFlags(mail.idRemoteMailbox, toDel, function(err) {
        if (err) {
          return callback(err);
        }
        return _this.addFlags(mail.idRemoteMailbox, toAdd, callback);
      });
    });
  };

  MailGetter.prototype.delFlags = function(uid, flags, callback) {
    if (flags.length === 0) {
      return callback(null);
    }
    return this.server.delFlags(uid, flags, callback);
  };

  MailGetter.prototype.addFlags = function(uid, flags, callback) {
    if (flags.length === 0) {
      return callback(null);
    }
    return this.server.addFlags(uid, flags, callback);
  };

  return MailGetter;

})();

module.exports = MailGetter;