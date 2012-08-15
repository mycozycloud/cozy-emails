BaseModel = require("./models").BaseModel

###

  Model which defines the new MAIL object (to send).

###
class exports.MailNew extends BaseModel
  
  url: "sendmail"

  initialize: ->
    @on "destroy", @removeView, @
    @on "change",  @redrawView, @