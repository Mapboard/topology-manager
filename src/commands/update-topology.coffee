{updateContacts} = require './update-contacts'
{updateFaces} = require './update-faces'
{cleanTopology} = require './clean-topology'
{db} = require '../util'
colors = require 'colors'

command = 'update [--reset] [--watch]'
describe = 'Update topology'

updateAll = (reset=false, verbose=false)->
  console.log "Updating contacts".green.bold
  await updateContacts()
  console.log "Updating faces".green.bold
  await updateFaces(reset)
  console.log "Cleaning topology".green.bold
  await cleanTopology()

startWatcher = ->
  updateInProgress = false
  needsUpdate = true
  runCommand = =>
    return if updateInProgress
    return unless needsUpdate

    updatInProgress = true
    needsUpdate = false
    await updateAll()
    updateInProgress = false

  conn = await db.connect direct: true
  conn.client.on 'notification', (data)->
    needsUpdate = true

  conn.none('LISTEN $1~', 'events')
  # Poll every second to see if we need to do things
  setInterval runCommand, 1000


handler = (argv)->
  if argv.watch
    startWatcher()
    return
  await updateAll(argv.reset)
  process.exit()

module.exports = {command, describe, handler, startWatcher}


