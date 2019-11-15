loader = require "tilelive-modules/loader"
{memoize} = require 'underscore'
Promise = require 'bluebird'
cache =  require("tilelive-cache")
tilelive = cache(require("@mapbox/tilelive"))
{db, sql: __sql} = require '../../../src/util.coffee'

sql = (id)->
  __sql require.resolve("../procedures/#{id}.sql")

interfaceFactory = (name, opts, buildTile)->
  {silent} = opts
  silent ?= false
  log = if silent then -> else console.log
  {id: layer_id, content_type, format} = await db.one sql('get-tile-metadata'), {name}
  q = sql 'get-tile'
  q2 = sql 'set-tile'
  getTile = (tileArgs)->
    {z,x,y} = tileArgs
    {tile} = await db.oneOrNone(q, {tileArgs..., layer_id}) or {}
    if not tile?
      log "Creating tile (#{z},#{x},#{y}) for layer #{name}"
      tile = await buildTile(tileArgs)
      db.none(q2, {z,x,y,tile,layer_id})
    return tile
  return {getTile, content_type, format, layer_id}

tileliveInterface = (name, uri)->
  uri += "?tileSize=512&scale=2"
  loader(tilelive, {})
  loadURI = Promise.promisify(tilelive.load)
  source = await loadURI(uri)
  opts = {context: source}
  getTile = Promise.promisify(source.getTile, opts)

  interfaceFactory name, (tileArgs)->
    {z,x,y} = tileArgs
    await getTile(z,x,y)

vectorTileInterface = (layer, opts={})->
  q = sql 'get-vector-tile'
  interfaceFactory layer, opts, (tileArgs)->
    {tile} = await db.one q, tileArgs
    return tile

module.exports = {vectorTileInterface, tileliveInterface}
