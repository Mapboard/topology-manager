{updateContacts} = require './update-contacts'
{updateFaces} = require './update-faces'
{cleanTopology} = require './clean-topology'
{db} = require '../util'
colors = require 'colors'

command = 'update [--reset] [--fill-holes] [--watch] [--fix-failed]'
describe = 'Update topology'

updateAll = (opts={})->
  {verbose, reset, fillHoles, fixFailed} = opts
  reset ?= false
  verbose ?= false
  fillHoles ?= false

  console.time('update')
  try
    console.log "Updating contacts".green.bold
    await updateContacts({fixFailed})
    console.log "Updating faces".green.bold
    await updateFaces({reset, fillHoles})
    console.log "Cleaning topology".green.bold
    await cleanTopology()
  catch err
    console.error err
  console.timeEnd('update')

startWatcher = ->
  updateInProgress = false
  needsUpdate = true
  runCommand = =>
    return if updateInProgress
    return unless needsUpdate

    updateInProgress = true
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
  {reset, fillHoles} = argv
  await updateAll({reset,fillHoles})
  process.exit()

module.exports = {command, describe, handler, startWatcher, updateAll}
