import 'babel-polyfill'
import {createStyle, createGeologySource} from './map-style'
import io from 'socket.io-client'
import {debounce} from 'underscore'
import mbxUtils from 'mapbox-gl-utils'

mapboxgl.accessToken = process.env.MAPBOX_TOKEN

ix = 0
oldID = "geology"
reloadGeologySource = (map)->
  layerIDs = [
    'unit'
    'bedrock-contact'
    'surface'
    'surficial-contact'
    'watercourse'
    'line'
  ]

  ix += 1
  newID = "geology-#{ix}"
  map.addSource(newID, createGeologySource())
  map.U.setLayerSource(layerIDs, newID)
  map.removeSource(oldID)
  oldID = newID

do ->
  style = await createStyle()

  map = new mapboxgl.Map {
    container: 'map',
    style
    center: [16.1987, -24.2254]
    zoom: 10
  }

  mbxUtils.init(map, mapboxgl)

  _ = ->
    console.log "Reloading map"
    reloadGeologySource(map)
  reloadMap = debounce(_, 500)

  socket = io()
  socket.on 'topology', (message)->
    console.log message
    reloadMap()
