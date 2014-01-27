// Generated by CoffeeScript 1.6.3
var Email, MailFolder, americano, async, queue;

async = require('async');

americano = require('americano-cozy');

queue = require('../lib/queue');

Email = require('./email');

module.exports = MailFolder = americano.getModel('MailFolder', {
  name: String,
  path: String,
  specialType: String,
  mailbox: String,
  imapLastFetchedId: {
    type: Number,
    "default": 0
  },
  mailsToBe: Object
});

MailFolder.prototype.log = function(msg) {
  return console.info("" + this + " " + ((msg != null ? msg.stack : void 0) || msg));
};

MailFolder.prototype.toString = function() {
  return "[Folder " + this.name + " " + this.id + " of Mailbox " + this.mailbox + "]";
};

MailFolder.findByMailbox = function(mailboxid, callback) {
  return MailFolder.request("byMailbox", {
    key: mailboxid
  }, callback);
};

MailFolder.byType = function(type, callback) {
  return MailFolder.request("byType", {
    key: type
  }, callback);
};

MailFolder.prototype.setupImport = function(getter, callback) {
  var path,
    _this = this;
  path = this.specialType === 'INBOX' ? 'INBOX' : this.path;
  return getter.openBox(path, function(err) {
    var abort;
    if (err) {
      return callback(err);
    }
    abort = function(msg, err) {
      _this.log(msg);
      if (err) {
        _this.log(err.stack);
      }
      return getter.closeBox(function() {
        return callback(err);
      });
    };
    return getter.getAllMails(function(err, results) {
      var data, id, ids, maxId, _i, _len;
      if (err) {
        return abort("Can't retrieve emails", err);
      }
      _this.log("Search query succeeded");
      if (results.length === 0) {
        return abort("No message to fetch");
      }
      _this.log("" + results.length + " mails to download");
      _this.log("Start grabing mail ids");
      maxId = 0;
      ids = [];
      for (_i = 0, _len = results.length; _i < _len; _i++) {
        id = results[_i];
        id = parseInt(id);
        if (id > maxId) {
          maxId = id;
        }
        ids.push(id);
      }
      data = {
        mailsToBe: ids,
        imapLastFetchedId: maxId
      };
      return _this.updateAttributes(data, function(err) {
        if (err) {
          return abort("can't save folder state", err);
        }
        _this.log("Finished saving ids to database");
        _this.log("max id = " + maxId);
        _this.log("folder " + _this.name + " setup is done");
        return getter.closeBox(callback);
      });
    });
  });
};

MailFolder.prototype.pushFetchTasks = function(getter) {
  var folder, getJob, id, mailToBe, path, _i, _len, _ref;
  if ((this.mailsToBe == null) || this.mailsToBe.length === 0) {
    this.log("Import: Nothing to download");
    return 0;
  } else {
    this.log("Import: " + this.mailsToBe.length + " mails to fetch");
  }
  path = this.specialType === 'INBOX' ? 'INBOX' : this.path;
  this.done = 0;
  this.total = this.mailsToBe.length;
  this.success = 0;
  this.oldpercent = 0;
  id = this.id;
  this.queue = queue();
  folder = this;
  _ref = this.mailsToBe;
  for (_i = 0, _len = _ref.length; _i < _len; _i++) {
    mailToBe = _ref[_i];
    getJob = function(folder, getter, remoteId, progress) {
      return function(queue, done) {
        var _this = this;
        return getter.fetchMail(remoteId, function(err, mail, attachments) {
          mail.folder = folder.id;
          return Email.create(mail, function(err, mail) {
            var msg;
            if (err) {
              return done(err);
            }
            msg = "New mail created: " + mail.idRemoteMailbox;
            msg += " " + mail.id + " [" + mail.subject + "] ";
            msg += JSON.stringify(mail.from);
            folder.log(msg);
            return mail.saveAttachments(attachments, function(err) {
              folder.done++;
              if (err) {
                folder.log('Mail creation error, skip this mail');
                console.log(err);
                return done();
              } else {
                queue.emit('success');
                folder.success++;
                folder.log("Imported " + folder.done + "/" + folder.total + " (" + folder.success + " ok)");
                return done();
              }
            });
          });
        });
      };
    };
    this.queue.push(getJob(folder, getter, mailToBe), false);
  }
  return this.queue;
};

MailFolder.prototype.fetchMessage = function(getter, remoteId, callback) {
  var _this = this;
  return getter.fetchMail(remoteId, function(err, mail, attachments) {
    mail.folder = _this.id;
    return Email.create(mail, function(err, mail) {
      var msg;
      if (err) {
        return callback(err);
      }
      msg = "New mail created: " + mail.idRemoteMailbox;
      msg += " " + mail.id + " [" + mail.subject + "] ";
      msg += JSON.stringify(mail.from);
      _this.log(msg);
      return mail.saveAttachments(attachments, function(err) {
        return callback(err, mail);
      });
    });
  });
};

MailFolder.prototype.getNewMails = function(getter, limit, callback) {
  var id, path, range,
    _this = this;
  id = Number(this.imapLastFetchedId) + 1;
  range = "" + id + ":" + (id + limit);
  this.log("Fetching new mails: " + range);
  path = this.specialType === 'INBOX' ? 'INBOX' : this.path;
  return getter.openBox(path, function(err) {
    var error, success;
    if (err) {
      return callback(err);
    }
    error = function(err) {
      return getter.closeBox(function(err) {
        _this.log(err);
        return callback(err);
      });
    };
    success = function(nbNewMails) {
      return getter.closeBox(function(err) {
        _this.log(err);
        return callback(null, nbNewMails);
      });
    };
    return getter.getMails(range, function(err, results) {
      var maxId;
      if (err) {
        return error(err);
      }
      maxId = id - 1;
      if (!results) {
        results = [];
      }
      return async.eachSeries(results, function(remoteId, callback) {
        _this.log("fetching mail : " + remoteId);
        return _this.fetchMessage(getter, remoteId, function(err, mail) {
          if (err) {
            return callback(err);
          }
          if (remoteId > maxId) {
            maxId = remoteId;
          }
          return callback(null);
        });
      }, function(getMailsErr) {
        if (maxId !== id - 1) {
          return _this.updateAttributes({
            imapLastFetchedId: maxId
          }, function(err) {
            if (err) {
              return error(err);
            }
            if (err) {
              return error(getMailsErr);
            }
            return _this.synchronizeChanges(getter, limit, function(err) {
              if (err) {
                _this.log(err);
              }
              return success(results.length);
            });
          });
        } else {
          return _this.synchronizeChanges(getter, limit, function(err) {
            if (err) {
              _this.log(err);
            }
            return success(results.length);
          });
        }
      });
    });
  });
};

MailFolder.prototype.synchronizeChanges = function(getter, limit, callback) {
  var _this = this;
  return getter.getLastFlags(this, limit, function(err, flagDict) {
    var query;
    if (err) {
      return callback(err);
    }
    query = {
      startkey: [_this.id, {}],
      endkey: [_this.id],
      limit: limit,
      descending: true
    };
    return Email.fromFolderByDate(query, function(err, mails) {
      var flags, mail, _i, _len;
      if (err) {
        return callback(err);
      }
      for (_i = 0, _len = mails.length; _i < _len; _i++) {
        mail = mails[_i];
        flags = flagDict[mail.idRemoteMailbox];
        if (flags != null) {
          mail.updateFlags(flags);
        }
      }
      return callback();
    });
  });
};

MailFolder.prototype.syncOneMail = function(getter, mail, newflags, callback) {
  var path,
    _this = this;
  this.log("Add read flag to mail " + mail.idRemoteMailbox);
  if (!mail.changedFlags(newflags)) {
    return;
  }
  path = this.specialType === 'INBOX' ? 'INBOX' : this.path;
  return getter.openBox(path, function(err) {
    if (err) {
      _this.log(err);
    }
    if (err) {
      return callback(err);
    }
    return getter.setFlags(mail, newflags, function(err) {
      return getter.closeBox(function(e) {
        if (!err) {
          _this.log("mail " + mail.idRemoteMailbox + " marked as seen");
          return mail.updateAttributes({
            flags: newflags
          }, callback);
        }
      });
    });
  });
};