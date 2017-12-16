{updateContacts} = require './update-contacts'
{updateFaces} = require './update-faces'
colors = require 'colors'

command = 'update [--reset]'
describe = 'Update topology'

handler = (argv)->
  console.log "Updating contacts".green.bold
  await updateContacts()
  console.log "Updating faces".green.bold
  await updateFaces(argv.reset)
  console.log "Cleaning topology".green.bold
  await cleanTopology()

  process.exit()

module.exports = {command, describe, handler}


