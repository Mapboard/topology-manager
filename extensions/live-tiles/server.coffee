appFactory = require 'tessera'
tilelive = require '@mapbox/tilelive'
express = require 'express'
responseTime = require "response-time"
cors = require 'cors'
morgan = require 'morgan'
loader = require "tilelive-modules/loader"
tileliveCache = require "tilelive-cache"

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
