appFactory = require 'tessera'
tilelive = require '@mapbox/tilelive'
express = require 'express'
responseTime = require "response-time"
cors = require 'cors'
morgan = require 'morgan'
loader = require "tilelive-modules/loader"
tileliveCache = require "tilelive-cache"
Promise = require 'bluebird'

loadTileLayer = (tilelive, uri)->
  app = express().disable("x-powered-by")
  tilelive.load uri, (e, source)->
    app.get '/:z/:x/:y.png', (req, res, next)->
      {z,x,y} = req.params
      source.getTile z,x,y, (err, tile, headers)->
        if err? then next(err)
        unless tile?
          return res.status(404).send("Not found")
        res.set(headers)
        return res.status(200).send(tile);
  return app

liveTileServer = (cfg)->
  {layers} = cfg['live-tiles']

  app = express().disable("x-powered-by")
  if process.env.NODE_ENV != "production"
    app.use(morgan("dev"))

  # Real tessera server caches, we don't.
  tilelive = require("@mapbox/tilelive")
  tilelive = tileliveCache(tilelive)

  loader(tilelive, {})

  app.get "/", (req,res)->
    res.send("Live tiles")

  for name, uri of layers
    prefix = "/#{name}"
    console.log prefix, uri
    app.use prefix, responseTime()
    app.use prefix, cors()
    # Uses `davenquinn/tessera`
    # so we don't have to load mapnik native modules
    # to run the tile server on weird architectures
    app.use prefix, loadTileLayer(tilelive, uri+"?tileSize=512&scale=2")

  return app

module.exports = liveTileServer
