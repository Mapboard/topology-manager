tilelive = require '@mapbox/tilelive'
express = require 'express'
responseTime = require "response-time"
cors = require 'cors'
morgan = require 'morgan'
loader = require "tilelive-modules/loader"
tileliveCache = require "tilelive-cache"
{memoize} = require 'underscore'
Promise = require 'bluebird'

tileFactory = memoize (uri)->
  loadURI = Promise.promisify(tilelive.load)
  source = await loadURI(uri)
  opts = {multiArgs: true, context: source}
  return Promise.promisify(source.getTile, opts)

handleTileRequest = (uri)->(req, res, next)->
  z = req.params.z | 0
  x = req.params.x | 0
  y = req.params.y | 0

  getTile = await tileFactory(uri)
  try
    [tile, headers] = await getTile z,x,y
    unless tile?
      return res.status(404).send("Not found")
    res.set(headers)
    return res.status(200).send(tile)
  catch err
    return next(err)

loadTileLayer = (tilelive, uri)->
  # Small replacement for tessera
  app = express().disable("x-powered-by")
  app.get '/:z/:x/:y.png', handleTileRequest(uri)
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
    app.use prefix, loadTileLayer(tilelive, uri+"?tileSize=512&scale=2")

  return app

module.exports = liveTileServer
