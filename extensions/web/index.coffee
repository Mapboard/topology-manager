import 'babel-polyfill'
import {createStyle} from './map-style'
import io from 'socket.io-client'

mapboxgl.accessToken = process.env.MAPBOX_TOKEN

do ->
  style = await createStyle()

  map = new mapboxgl.Map {
    container: 'map',
    style
    center: [16.1987, -24.2254]
    zoom: 10
  }

  socket = io()
  socket.on 'topology', (message)->
    console.log message
