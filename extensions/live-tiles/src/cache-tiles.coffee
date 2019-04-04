SphericalMercator = require '@mapbox/sphericalmercator'
Promise = require 'bluebird'

{tileFactory} = require './tile-factory'
cfg = require '../../../src/config'

command = 'cache-tiles [--all]'
describe = 'Cache tile layers'

merc = new SphericalMercator {size: 256}

tileCoords = (zoomLevels, bounds)->
  for z in zoomLevels
    {minX, maxX, minY, maxY} = merc.xyz(bounds, z)
    for x in [minX..maxX]
      for y in [minY..maxY]
        yield {z,x,y}

handler = ->

  {layers, bounds, zoomRange} = cfg['live-tiles']
  zoomLevels = [zoomRange[0]..zoomRange[1]]

  total = 0
  for z in zoomLevels
    {minX, maxX, minY, maxY} = merc.xyz(bounds, z)
    n = (maxX-minX)*(maxY-minY)
    total += n
    console.log "zoom #{z}: #{n} tiles"
  console.log "  total: #{total} tiles"


  for name, lyr of layers
    getTile = await tileFactory(lyr)
    coords = tileCoords(zoomLevels, bounds)
    fn = ({z,x,y})->
      await getTile z,x,y

    Promise.map(coords, fn, {concurrency: 8})

module.exports = {command, describe, handler}

