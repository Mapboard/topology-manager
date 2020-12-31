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
  if nlines == 0
    console.log("No contacts to update")

  rows = await db.query getContacts
  remaining = rows.length
  __ = 'Updating lines :bar :current/:total (:elapsed/:eta s)'
  bar = new ProgressBar(__, { total: remaining })
  while remaining > 0
    n = 10
    try
      result = await db.query proc, {n}
      for {id, err} in result
        if err?
          bar.interrupt "#{id}".gray+" #{err}".red.dim
    catch err
      console.error(err)
      bar.interrupt "#{err}".red.dim
    bar.tick(result.length)
    remaining -= result.length

  # Post-update (in an ideal world we would not have to do this)
  #console.log "Linking lines to topology edges".gray
  await db.query postUpdateContacts

handler = (argv)->
  await updateContacts(argv)
  process.exit()

module.exports = {command, describe, handler, updateContacts}

