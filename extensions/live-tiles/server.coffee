appFactory = require './tessera'
tilelive = require '@mapbox/tilelive'
express = require 'express'
responseTime = require "response-time"
cors = require 'cors'
morgan = require 'morgan'
loader = require "tilelive-modules/loader"
tileliveCache = require "tilelive-cache"
Promise = require 'bluebird'

loadTileLayer = (tilelive, uri)->
  # Small replacement for tessera
  app = express().disable("x-powered-by")
  app.get '/:z/:x/:y.png', (req, res, next)->
    {z,x,y} = req.params
    console.log z,x,y
    tilelive.load uri, (e, source)->
      if e? then return next(e)
      console.log source
      source.getTile z,x,y, (err, tile, headers)->
        console.log tile
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
    app.use prefix, appFactory(tilelive, uri+"?tileSize=512&scale=2")

  return app

module.exports = liveTileServer
