import {get} from 'axios'

geology = {
  type: "vector",
  tiles: [
    "http://localhost:3006/live-tiles/map-data/{z}/{x}/{y}.pbf",
  ],
  maxzoom: 15
  minzoom: 10
}

createStyle = ->

  {data} = await get "/polygon/types"
  colors = {}
  for d in data
    colors[d.id] = d.color

  return {
    version: 8
    name: "Geology"
    sources: {
      geology
    }
    layers: [
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
        "id": "surface",
        "source": "geology",
        "source-layer": "surficial",
        "type": "fill",
        "paint": {
          "fill-color": ['get', ['get', 'unit_id'], ['literal', colors]]
        }
      }

      #{
        #"id": "contact",
        #"source": "geology",
        #"source-layer": "polygon",
        #"type": "line",
        #"paint": {
          #"line-color": "#000000"
        #}
      #}
    ]
  }

export {createStyle}
