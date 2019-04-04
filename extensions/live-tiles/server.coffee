tilelive = require '@mapbox/tilelive'
express = require 'express'
responseTime = require "response-time"
cors = require 'cors'
morgan = require 'morgan'
loader = require "tilelive-modules/loader"
tileliveCache = require "tilelive-cache"
Promise = require 'bluebird'

loadURI = Promise.promisify(tilelive.load)

loadTileLayer = (tilelive, uri)->
  # Small replacement for tessera
  app = express().disable("x-powered-by")
  source = await loadURI(uri)
  app.get '/:z/:x/:y.png', (req, res, next)->
    z = req.params.z | 0
    x = req.params.x | 0
    y = req.params.y | 0
    source.getTile z,x,y, (err, tile, headers)->
      if err? then next(err)
      unless tile?
        return res.status(404).send("Not found")
      res.set(headers)
      return res.status(200).send(tile)
  return app

liveTileServer = (cfg)->
  {layers} = cfg['live-tiles']

  app = express().disable("x-powered-by")
  if process.env.NODE_ENV != "production"
    app.use(morgan("dev"))

  loader(tilelive, {})

  app.get "/", (req,res)->
    res.send("Live tiles")

  for name, uri of layers
    prefix = "/#{name}"
    app.use prefix, responseTime()
    app.use prefix, cors()
    # Uses `davenquinn/tessera`
    # so we don't have to load mapnik native modules
    # to run the tile server on weird architectures
    loadTileLayer(tilelive, uri+"?tileSize=512&scale=2")
      .then (d)->app.use(prefix, d)

  return app

module.exports = liveTileServer
