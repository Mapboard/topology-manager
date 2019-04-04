express = require 'express'
responseTime = require "response-time"
cors = require 'cors'
morgan = require 'morgan'
{tileFactory} = require './src/tile-factory'

handleTileRequest = (uri)->(req, res, next)->
  z = req.params.z | 0
  x = req.params.x | 0
  y = req.params.y | 0

  try
    getTile = await tileFactory(uri)
    # Ignore headers that are also set by getTile
    tile = await getTile z,x,y
    unless tile?
      return res.status(404).send("Not found")
    res.set({'Content-Type':'image/png'})
    return res.status(200).send(tile)
  catch err
    return next(err)

loadTileLayer = (uri)->
  # Small replacement for tessera
  app = express().disable("x-powered-by")
  app.get '/:z/:x/:y.png', handleTileRequest(uri)
  return app

liveTileServer = (cfg)->
  {layers} = cfg['live-tiles']

  app = express().disable("x-powered-by")
  if process.env.NODE_ENV != "production"
    app.use(morgan("dev"))

  app.get "/", (req,res)->
    res.send("Live tiles")

  for name, uri of layers
    prefix = "/#{name}"
    app.use prefix, responseTime()
    app.use prefix, cors()
    # Uses `davenquinn/tessera`
    # so we don't have to load mapnik native modules
    # to run the tile server on weird architectures
    app.use prefix, loadTileLayer(uri)

  return app

module.exports = liveTileServer
