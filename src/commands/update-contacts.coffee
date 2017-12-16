{db,sql} = require '../util'
colors = require 'colors'

command = 'update-contacts'
describe = 'Update topology for contacts'

count = "SELECT count(*) nlines
         FROM map_digitizer.linework
         WHERE geometry_hash IS null"
proc = sql('procedures/update-contact')

updateContacts = ->
  {nlines} = await db.one count
  console.log "#{nlines} remaining"
  while nlines > 0
    try
      await db.query proc
    catch err
      console.error "#{err}".red
      process.exit(1)
    {nlines} = await db.one count
    console.log "#{nlines} remaining"

handler = ->
  await updateContacts()
  process.exit()

module.exports = {command, describe, handler, updateContacts}

