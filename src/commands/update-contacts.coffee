{db,sql} = require '../util'
colors = require 'colors'

command = 'update-contacts'
describe = 'Update topology for contacts'

count = sql('procedures/count-contact')
proc = sql('procedures/update-contact')

updateContacts = ->
  {nlines} = await db.one count
  console.log "#{nlines} remaining"
  while nlines > 0
    try
      {e} = await db.query proc
      console.log(e) if e?
    catch err
      console.error "#{err}".red
      return
    {nlines} = await db.one count
    console.log "#{nlines} remaining"

handler = ->
  await updateContacts()
  process.exit()

module.exports = {command, describe, handler, updateContacts}

