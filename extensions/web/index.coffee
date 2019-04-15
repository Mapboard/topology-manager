import style from '../live-tiles/src/map-style'


mapboxgl.accessToken = process.env.MAPBOX_TOKEN

map = new mapboxgl.Map {
  container: 'map',
  style: style
  center: [16.1987, -24.2254]
  zoom: 10
}
