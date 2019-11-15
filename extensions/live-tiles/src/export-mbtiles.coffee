SphericalMercator = require '@mapbox/sphericalmercator'
Promise = require 'bluebird'
{promisify} = require 'util'
{SingleBar} = require('cli-progress')
MBTiles = require '@mapbox/mbtiles'

{vectorTileInterface} = require './tile-factory'
cfg = require '../../../src/config'

command = 'export-mbtiles [--layer LYR] [--zoom-range MIN,MAX] FILE'
describe = 'Export a Mapbox Studio compatible vector tileset'

merc = new SphericalMercator {size: 256}

tileCoords = (zoomLevels, bounds)->
  for z in zoomLevels
    {minX, maxX, minY, maxY} = merc.xyz(bounds, z)
    for x in [minX..maxX]
      for y in [minY..maxY]
        yield {z,x,y}

handler = (argv)->
  filename = argv.FILE
  layer = argv.LYR or 'map-data'

  {bounds, zoomRange} = cfg['live-tiles']
  if argv.zoomRange?
    zoomRange = argv.zoomRange.split(",").map (d)->
      parseInt(d.trim())

  zoomLevels = [zoomRange[0]..zoomRange[1]]

  total = 0
  for z in zoomLevels
    {minX, maxX, minY, maxY} = merc.xyz(bounds, z)
    n = (maxX-minX)*(maxY-minY)
    total += n
    console.log "zoom #{z}: #{n} tiles"
  console.log "  total: #{total} tiles"

  [minzoom, maxzoom] = zoomRange

  data = {
    name: "geologic-map",
    description:"Geologic map data",
    format,
    version: 2,
    minzoom
    maxzoom
    bounds: bounds.map(toString).join(",")
    type: "overlay"
    json: JSON.stringify {
      vector_layers: [
        {id: layer, description: "", minzoom, maxzoom, fields: {}}
      ]
    }
  }

  mbtiles = await new (promisify(MBTiles))(filename+"?mode=rwc")
  mbtOp = (name, rest...)->
    promisify(mbtiles[name].bind(mbtiles))(rest...)

  # Actually write everything
  await mbtOp('startWriting')
  await mbtOp('putInfo', data)

  progressBar = new SingleBar()
  progressBar.start(total)

  {getTile, format} = await vectorTileInterface(layer, {silent: true})
  coords = tileCoords(zoomLevels, bounds)
  fn = ({z,x,y})->
    tile = await getTile {z,x,y}
    await mbtOp('putTile', z,x,y, tile)
    progressBar.increment()

  # Insert actual tiles
  await Promise.mapSeries(coords, fn, {concurrency: 8})

  await mbtOp('stopWriting')
  progressBar.stop()


module.exports = {command, describe, handler}


