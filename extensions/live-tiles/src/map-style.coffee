geology = {
  type: "vector",
  tiles: [
    "/live-tiles/map-data/{z}/{x}/{y}.pbf",
  ],
  maxzoom: 15
  minzoom: 12
}

module.exports = {
  version: 8
  name: "Geology"
  sources: {
    geology
  }
}
