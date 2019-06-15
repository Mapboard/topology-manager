express = require 'express'
responseTime = require "response-time"
cors = require 'cors'
morgan = require 'morgan'
{vectorTileInterface} = require './src/tile-factory'
{db} = require '../../src/util.coffee'

tileLayerServer = ({getTile, content_type, format, layer_id})->
  # Small replacement for tessera

  prefix = "/#{layer_id}"

  app = express().disable("x-powered-by")
  app.use prefix, responseTime()
  app.use prefix, cors()

  app.get "/:z/:x/:y.#{format}", (req, res, next)->
    z = req.params.z | 0
    x = req.params.x | 0
    y = req.params.y | 0

    try
      # Ignore headers that are also set by getTile
      tile = await getTile {z,x,y, layer_id}
      unless tile?
        return res.status(404).send("Not found")
      res.set({'Content-Type': content_type})
      return res.status(200).send(tile)
    catch err
      return next(err)

  return app

startWatcher = ->
  console.log 'Starting topology watcher'
  # Listen for data
  conn = await db.connect {direct: true}
  conn.client.on 'notification', (data)->
    console.log "Topology: #{data.payload}"

  conn.none('LISTEN $1~', 'topology')

liveTileServer = (cfg)->
  {layers} = cfg['live-tiles']

  app = express().disable("x-powered-by")
  if process.env.NODE_ENV != "production"
    app.use(morgan("dev"))

  app.get "/", (req,res)->
    res.send("Live tiles")

  vectorTileInterface 'map-data'
    .then (cfg)->
      server = tileLayerServer cfg
      app.use "/map-data", server

  startWatcher()

  return app

module.exports = liveTileServer
