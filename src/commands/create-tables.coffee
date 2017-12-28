glob = require 'glob-promise'
{__base, proc} = require '../util'
colors = require 'colors'

command = 'create-tables'
describe = 'Create tables'

handler = (argv)->
  try
    for fn in await glob('fixtures/*.sql', cwd: __base)
      await proc(fn)
    await proc('extensions/map-digitizer.sql')
  catch err
    console.log "Exiting on #{err}".red
    process.exit()
  process.exit()

module.exports = {command, describe, handler}


