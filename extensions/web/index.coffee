
mapboxgl.accessToken = process.env.MAPBOX_TOKEN

map = new mapboxgl.Map {
  container: 'map',
  style: 'mapbox://styles/mapbox/streets-v9'
  center: [16.1987, -24.2254]
  zoom: 10
}
