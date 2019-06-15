{server, data_schema, connection} = require '../../src/config'
{startWatcher} = require '../../src/commands/update'
appFactory = require './map-digitizer-server/src/feature-server'
{join} = require 'path'

command = 'serve'
describe = 'Create a feature server'

handler = ->
  server ?= {}
  {tiles, port} = server
  tiles ?= {}
  port ?= 3006
  app = appFactory {connection, tiles, schema: data_schema}
  app.set 'views', join(__dirname, 'views')
  app.set 'view engine', 'pug'

  app.get '/', (req,res)->
    res.render 'map.pug', {
      title: 'Geologic Map', message: 'Hello there!'
      endpoints: Object.keys(tiles)
    }

  server = app.listen port, ->
    console.log "Listening on port #{server.address().port}"
    startWatcher(verbose=false)

module.exports = {command, describe, handler}
