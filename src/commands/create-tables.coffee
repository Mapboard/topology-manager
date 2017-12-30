glob = require 'glob-promise'
{__base, proc} = require '../util'
{extensions} = require '../config'
{join} = require 'path'
colors = require 'colors'

command = 'create-tables'
describe = 'Create tables'

handler = (argv)->
  try
    for fn in await glob('fixtures/*.sql', cwd: __base)
      await proc(fn)
    await proc('extensions/map-digitizer.sql')

    for e in extensions
      {fixtures, path} = e
      continue unless fixtures
      console.log "Extension "+e.name.green.bold
      console.log e.description.green.dim
      console.log ""
      if typeof fixtures == 'string'
        __dir = join(path, fixtures)
        fixtures = await glob('*.sql', cwd: __dir)
      for fn in fixtures
        p = join __dir, fn
        await proc(p)

  catch err
    console.log "#{err.stack}".red
    process.exit()
  process.exit()

module.exports = {command, describe, handler}


