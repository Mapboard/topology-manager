loader = require "tilelive-modules/loader"
{memoize} = require 'underscore'
Promise = require 'bluebird'
cache =  require("tilelive-cache")
tilelive = cache(require("@mapbox/tilelive"))
{db, sql: __sql} = require '../../../src/util.coffee'

sql = (id)->
  __sql require.resolve("../procedures/#{id}.sql")

tileFactory = (buildTile)->
  q = sql 'get-tile'
  (z,x,y)->
    {tile} = await db.oneOrNone(q, {z,x,y}) or {}
    if not tile?
      tile = await buildTile(z,x,y)
    return tile

tileliveTileFactory = memoize (input)->
  uri = input+"?tileSize=512&scale=2"
  loader(tilelive, {})
  loadURI = Promise.promisify(tilelive.load)
  source = await loadURI(uri)
  opts = {context: source}
  getTile = Promise.promisify(source.getTile, opts)

  q2 = sql 'set-tile'

  tileFactory (z,x,y)->
    console.log "Creating tile: #{z} #{x} #{y}"
    tile = await getTile(z,x,y)
    db.none(q2, {z,x,y,tile})
    return tile

vectorTileFactory = (layer)->
  q = sql 'get-vector-tile'
  (z,x,y)->
    

module.exports = {tileFactory}
