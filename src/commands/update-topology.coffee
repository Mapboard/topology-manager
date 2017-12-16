{updateContacts} = require './update-contacts'
{updateFaces} = require './update-faces'
colors = require 'colors'

command = 'update [--reset]'
describe = 'Update topology'

handler = (argv)->
  console.log "Updating contacts"
  await updateContacts()
  console.log "Updating faces"
  await updateFaces(argv.reset)
  process.exit()

module.exports = {command, describe, handler}


