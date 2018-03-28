ProgressBar = require 'progress'
{db,sql} = require '../util'
colors = require 'colors'

command = 'update-contacts [--fix-failed]'
describe = 'Update topology for contacts'

count = sql('procedures/count-contact')
proc = sql('procedures/update-contact')
resetErrors = sql('procedures/reset-linework-errors')
postUpdateContacts = sql('procedures/post-update-contacts')

updateContacts = (opts={})->
  {fixFailed} = opts
  fixFailed ?= false

  if fixFailed
    await db.query resetErrors

  {nlines} = await db.one count
  __ = 'Updating lines :bar :current/:total (:elapsed/:eta s)'
  bar = new ProgressBar(__, { total: nlines })
  while nlines > 0
    try
      [{e}] = await db.query proc
      if e?
        bar.interrupt "#{e}".red.dim
    catch err
      bar.interrupt "#{err}".red
      continue
    bar.tick()
    {nlines} = await db.one count

  # Post-update (in an ideal world we would not have to do this)
  console.log "Linking lines to topology edges".gray
  await db.query postUpdateContacts

handler = (argv)->
  await updateContacts(argv)
  process.exit()

module.exports = {command, describe, handler, updateContacts}

