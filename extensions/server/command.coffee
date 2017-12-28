{server, data_schema, connection} = require '../../src/config'
{startWatcher} = require '../../src/commands/update-topology'
{appFactory} = require 'map-digitizer-server'

command = 'serve'
describe = 'Create a feature server'

handler = (argv)->
  {tiles, port} = server
  app = appFactory {connection, tiles, schema: data_schema}
  server = app.listen port, ->
    console.log "Listening on port #{server.address().port}"
    startWatcher()

module.exports = {command, describe, handler}


