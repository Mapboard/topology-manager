tilelive = require '@mapbox/tilelive'
loader = require "tilelive-modules/loader"
{memoize} = require 'underscore'
Promise = require 'bluebird'
{db, sql: __sql} = require '../../../src/util.coffee'

sql = (id)->
  __sql require.resolve("../procedures/#{id}.sql")

tileFactory = memoize (input)->
  uri = input+"?tileSize=512&scale=2"
  loader(tilelive, {})
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

module.exports = {tileFactory}
