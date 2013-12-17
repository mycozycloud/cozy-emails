{MessageBoxElement} = require "views/message_box_element"
{LogMessage} = require "models/logmessage"

###
        @file: message_box.coffee
        @author: Mikolaj Pawlikowski (mikolaj@pawlikowski.pl/seeker89@github)
        @description:
            Serves a place to display messages which are meant to be seen by user.
###

class exports.MessageBox extends Backbone.View

    id: "message_box"

    constructor: (@el, @collection) ->
        super()

    initialize: ->
        @collection.on "add", @renderOne
        @collection.on "reset", @render

    renderOne: (logmessage) =>
        @addNewBox logmessage
        if logmessage.get("subtype") is "check" and
        logmessage.get("type") is "info"
            logmessage.url = "logs/#{logmessage.id}"
            logmessage.destroy()


    # Add a new box widget to UI.
    addNewBox: (logmessage) ->
        box = new MessageBoxElement logmessage, @collection
        @$el.prepend box.render().el

    render: =>
        @previousCheckMessage = null
        @collection.each (message) =>
            @renderOne message
        @
