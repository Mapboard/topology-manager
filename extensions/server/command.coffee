{db} = require '../../src/util.coffee'
cfg = require '../../src/config'
{startWatcher} = require '../../src/commands/update'
appFactory = require 'mapboard-server'
express = require 'express'
{join} = require 'path'
http = require 'http'

command = 'serve'
describe = 'Create a feature server'

{server, data_schema, connection} = cfg

handler = ->
  server ?= {}
  {tiles, port} = server
  tiles ?= {}
  port ?= 3006
  app = appFactory {connection, tiles, schema: data_schema, createFunctions: false}

  app.use express.static join(__dirname,'..','web','dist')

  # This should be conditional
  {liveTileServer, topologyWatcher} = require '../live-tiles/server'
  app.use('/live-tiles', liveTileServer(cfg))

  server = http.createServer(app)
  topologyWatcher(db, server)
  startWatcher(verbose=false)

  server.listen port, ->
    console.log "Listening on port #{port}"

module.exports = {command, describe, handler}
