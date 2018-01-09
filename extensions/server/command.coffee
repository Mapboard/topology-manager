{server, data_schema, connection} = require '../../src/config'
{startWatcher} = require '../../src/commands/update-topology'
{appFactory} = require 'map-digitizer-server'

command = 'serve'
describe = 'Create a feature server'

handler = ->
  {tiles, port} = server
  port ?= 3006
  app = appFactory {connection, tiles, schema: data_schema}
  server = app.listen port, ->
    console.log "Listening on port #{server.address().port}"
    startWatcher(verbose=false)

module.exports = {command, describe, handler}


