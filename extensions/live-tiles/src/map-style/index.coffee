baseStyle = require './base-style.json'

createGeologySource = (host)->
  {
    type: "vector",
    tiles: [
      "#{host}/live-tiles/map-data/{z}/{x}/{y}.pbf",
    ],
    maxzoom: 15
    minzoom: 5
  }

createStyle = (polygonTypes, hostName)->
  hostName ?= 'http://localhost:3006'

  colors = {}
  for d in polygonTypes
    colors[d.id] = d.color

  geologyLayers = [
    {
      "id": "unit",
      "source": "geology",
      "source-layer": "bedrock",
      "type": "fill",
      "paint": {
        "fill-color": ['get', ['get', 'unit_id'], ['literal', colors]]
      }
    }
    {
      "id": "bedrock-contact",
      "source": "geology",
      "source-layer": "contact",
      "type": "line",
      "layout": {
        "line-cap": "round"
      }
      "paint": {
        "line-color": "#000000"
        "line-width": [
            'interpolate',
            ['exponential', 2],
            ['zoom'],
            10, ["*", 3, ["^", 2, -6]],
            24, ["*", 3, ["^", 2, 8]]
        ]
      }
      #filter: ["!", ["match", "surficial", ["get", "type"]]]
    }
    {
      "id": "surface",
      "source": "geology",
      "source-layer": "surficial",
      "type": "fill",
      "paint": {
        "fill-color": ['get', ['get', 'unit_id'], ['literal', colors]]
      }
    }
    # {
    #   "id": "surficial-contact",
    #   "source": "geology",
    #   "source-layer": "contact",
    #   "type": "line",
    #   "paint": {
    #     "line-color": "#ffbe17"
    #   }
    #   filter: ["match", "surficial", ["get", "type"]]
    # }
    {
      "id": "watercourse",
      "source": "geology",
      "source-layer": "line",
      "type": "line",
      "paint": {
        "line-color": "#3574AC"
        "line-width": 1
      }
      filter: ["==", "watercourse", ["get", "type"]]
    }
    {
      "id": "line",
      "source": "geology",
      "source-layer": "line",
      "type": "line",
      "paint": {
        "line-color": "#cccccc"
      }
      filter: ["!=", "watercourse", ["get", "type"]]
    }
  ]

  style = {baseStyle...}

  style.sources.geology = createGeologySource(hostName)

  style.layers = [
    baseStyle.layers...
    geologyLayers...
  ]

  #style.geologyLayers = geologyLayers



  return style


module.exports = {createStyle, createGeologySource}
