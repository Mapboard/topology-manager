ProgressBar = require 'progress'
{db,sql} = require '../util'
colors = require 'colors'
Promise = require 'bluebird'

command = 'update-contacts [--fix-failed]'
describe = 'Update topology for contacts'

count = sql('procedures/count-contact')
proc = sql('procedures/update-contact')
resetErrors = sql('procedures/reset-linework-errors')
getContacts = sql('procedures/get-contacts-to-update')
postUpdateContacts = sql('procedures/post-update-contacts')

updateContacts = (opts={})->
  {fixFailed} = opts
  fixFailed ?= false

  if fixFailed
    await db.query resetErrors

  {nlines} = await db.one count
  rows = await db.query getContacts
  __ = 'Updating lines :bar :current/:total (:elapsed/:eta s)'
  bar = new ProgressBar(__, { total: rows.length })
  mapFn = ({id})->
    try
      {err} = await db.one proc, {id}
      if err?
        throw err
    catch err
      bar.interrupt "#{err}".red.dim
    bar.tick()
  await Promise.map rows, mapFn, {concurrency: 1}

  # Post-update (in an ideal world we would not have to do this)
  console.log "Linking lines to topology edges".gray
  await db.query postUpdateContacts

handler = (argv)->
  await updateContacts(argv)
  process.exit()

module.exports = {command, describe, handler, updateContacts}

