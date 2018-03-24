{db,sql} = require '../util'
colors = require 'colors'

command = 'update-contacts [--fix-failed]'
describe = 'Update topology for contacts'

count = sql('procedures/count-contact')
proc = sql('procedures/update-contact')
resetErrors = sql('procedures/reset-linework-errors')

updateContacts = (opts={})->
  {fixFailed} = opts
  fixFailed ?= false

  if fixFailed
    await db.query resetErrors

  {nlines} = await db.one count
  console.log "#{nlines} remaining"
  while nlines > 0
    try
      [{e}] = await db.query proc
      if e?
        console.error "#{e}".red
    catch err
      console.error "#{err}".red
      continue
    {nlines} = await db.one count
    console.log "#{nlines} remaining"

handler = (argv)->
  await updateContacts(argv)
  process.exit()

module.exports = {command, describe, handler, updateContacts}

