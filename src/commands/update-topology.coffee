{updateContacts} = require './update-contacts'
{updateFaces} = require './update-faces'
{cleanTopology} = require './clean-topology'
{db} = require '../util'
colors = require 'colors'

command = 'update [--reset] [--watch]'
describe = 'Update topology'

updateAll = (reset=false)->
  console.log "Updating contacts".green.bold
  await updateContacts()
  console.log "Updating faces".green.bold
  await updateFaces(reset)
  console.log "Cleaning topology".green.bold
  await cleanTopology()

startWatcher = ->
  updateAll()
  conn = await db.connect direct: true
  conn.client.on 'notification', (data)->
    console.log('Received:', data)
    updateAll()
  conn.none('LISTEN $1~', 'events')

handler = (argv)->
  if argv.watch
    startWatcher()
    return
  updateAll(argv.reset)
  process.exit()

module.exports = {command, describe, handler}


