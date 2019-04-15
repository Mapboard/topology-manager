geology = {
  type: "vector",
  tiles: [
    "http://localhost:3006/live-tiles/map-data/{z}/{x}/{y}.pbf",
  ],
  maxzoom: 15
  minzoom: 10
}

module.exports = {
  version: 8
  name: "Geology"
  sources: {
    geology
  }
  layers: [
    {
      "id": "water",
      "source": "geology",
      "source-layer": "polygon",
      "type": "fill",
      "paint": {
        "fill-color": "#0000ff"
      }
    }
    {
      "id": "contact",
      "source": "geology",
      "source-layer": "polygon",
      "type": "line",
      "paint": {
        "line-color": "#000000"
      }
    }
  ]
}
