import {get} from 'axios'
import baseStyle from './base-style.json'

createGeologySource = ->
  {
    type: "vector",
    tiles: [
      "http://localhost:3006/live-tiles/map-data/{z}/{x}/{y}.pbf",
    ],
    maxzoom: 15
    minzoom: 5
  }

createStyle = ->

  {data} = await get "/polygon/types"
  colors = {}
  for d in data
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
      "paint": {
        "line-color": "#000000"
      }
      filter: ["!=", "surficial", ["get", "type"]]
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
    {
      "id": "surficial-contact",
      "source": "geology",
      "source-layer": "contact",
      "type": "line",
      "paint": {
        "line-color": "#ffbe17"
      }
      filter: ["==", "surficial", ["get", "type"]]
    }
    {
      "id": "watercourse",
      "source": "geology",
      "source-layer": "line",
      "type": "line",
      "paint": {
        "line-color": "#3574AC"
      }
      filter: ["==", "watercourse", ["get", "type"]]
    }
    {
      "id": "line",
      "source": "geology",
      "source-layer": "line",
      "type": "line",
      "paint": {
        "line-color": "#000000"
      }
      filter: ["!=", "watercourse", ["get", "type"]]
    }
  ]

  style = baseStyle

  style.sources.geology = createGeologySource()

  style.layers = [
    baseStyle.layers...
    geologyLayers...
  ]

  style.geologyLayers = geologyLayers

  return style


export {createStyle, createGeologySource}
