express = require 'express'
responseTime = require "response-time"
cors = require 'cors'
morgan = require 'morgan'
{vectorTileInterface} = require './src/tile-factory'
{db, sql} = require '../../src/util.coffee'
{createStyle} = require './src/map-style'

tileLayerServer = ({getTile, content_type, format, layer_id})->
  # Small replacement for tessera

  prefix = "/#{layer_id}"

  app = express().disable("x-powered-by")
  app.use prefix, responseTime()
  app.use prefix, cors()

  app.get "/:z/:x/:y.#{format}", (req, res, next)->
    z = req.params.z | 0
    x = req.params.x | 0
    y = req.params.y | 0

    try
      # Ignore headers that are also set by getTile
      tile = await getTile {z,x,y, layer_id}
      unless tile?
        return res.status(404).send("Not found")
      res.set({'Content-Type': content_type})
      return res.status(200).send(tile)
    catch err
      return next(err)

  return app

liveTileServer = (cfg)->
  app = express().disable("x-powered-by")
  if process.env.NODE_ENV != "production"
    app.use(morgan("dev"))

  app.get "/", (req,res)->
    res.send("Live tiles")

  vectorTileInterface 'map-data'
    .then (cfg)->
      server = tileLayerServer cfg
      app.use "/map-data", server

  app.get "/style.json", (req, res)->
    fn = require.resolve("../server/map-digitizer-server/sql/get-feature-types.sql")
    polygonTypes = await db.query sql(fn), {schema: 'map_digitizer', table: 'polygon_type'}
    res.json(createStyle(polygonTypes, "http://Daven-Quinn.local:3006"))

  return app

module.exports = {liveTileServer}
