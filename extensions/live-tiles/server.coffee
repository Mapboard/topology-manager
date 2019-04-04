tilelive = require '@mapbox/tilelive'
express = require 'express'
responseTime = require "response-time"
cors = require 'cors'
morgan = require 'morgan'
loader = require "tilelive-modules/loader"
tileliveCache = require "tilelive-cache"
{memoize} = require 'underscore'
Promise = require 'bluebird'
{db, sql: __sql} = require '../../src/util.coffee'

sql = (id)->
  __sql require.resolve("./procedures/#{id}.sql")

tileFactory = memoize (uri)->
  loadURI = Promise.promisify(tilelive.load)
  source = await loadURI(uri)
  opts = {context: source}
  getTile = Promise.promisify(source.getTile, opts)

  q = sql 'get-tile'
  q2 = sql 'set-tile'
  buildTile = (z,x,y)->
    console.log "Creating tile: #{z} #{x} #{y}"
    tile = await getTile(z,x,y)
    db.none(q2, {z,x,y,tile})
    return tile

  (z,x,y)->
    {tile} = await db.oneOrNone(q, {z,x,y}) or {}
    if not tile?
      tile = await buildTile(z,x,y)
    return tile

handleTileRequest = (uri)->(req, res, next)->
  z = req.params.z | 0
  x = req.params.x | 0
  y = req.params.y | 0

  getTile = await tileFactory(uri)
  try
    # Ignore headers that are also set by getTile
    tile = await getTile z,x,y
    unless tile?
      return res.status(404).send("Not found")
    res.set({'Content-Type':'image/png'})
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
