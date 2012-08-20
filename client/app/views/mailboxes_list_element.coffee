{Mailbox} = require "../models/mailbox"

###

  The element of the list of mailboxes.
  
  mailboxes_list -> mailboxes_list_element

###
class exports.MailboxesListElement extends Backbone.View
  className: "mailbox_well well"
  tagName: "div"
  isEdit: false
  
  events:
    "click .edit_mailbox" : "buttonEdit"
    "click .cancel_edit_mailbox" : "buttonCancel"
    "click .save_mailbox" : "buttonSave"
    "click .delete_mailbox" : "buttonDelete"

  constructor: (@model, @collection) ->
    super()
    @model.view = @

  # enter edit mode
  buttonEdit: (event) ->
    @model.isEdit = true
    @render()
    
  # quit edit mode, no changes saved
  buttonCancel: (event) ->
    @model.isEdit = false
    @render()
    
  # save changes to server
  buttonSave: (event) ->    
    $(event.target).addClass("disabled").removeClass("buttonSave")  
    input = @.$(".content")
    data = {}
    input.each (i) ->
      data[input[i].id] = input[i].value;
    @model.save data
    @collection.trigger("update_menu")
    @model.isEdit = false
    @render()
    
  # delete the mailbox
  buttonDelete: (event) =>
    $(event.target).addClass("disabled").removeClass("delete_mailbox")
    @model.destroy()

  render: ->
    # whether we should activate the edit mode or not
    if @model.isEdit
      template = require('./templates/_mailbox/mailbox_edit')
    else
      template = require('./templates/_mailbox/mailbox')
    $(@el).html template("model": @model)
    @