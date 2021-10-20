import axios from "axios";
import { createLineSymbolLayers } from "./symbol-layers";

const createGeologySource = (host) => ({
  type: "vector",
  tiles: [`${host}/live-tiles/map-data/{z}/{x}/{y}.pbf`],
  maxzoom: 15,
  minzoom: 5,
});

function createBasicStyle(baseStyle) {
  let style = { ...baseStyle };
  style.sources["mapbox-dem"] = {
    type: "raster-dem",
    url: "mapbox://mapbox.mapbox-terrain-dem-v1",
    tileSize: 512,
    maxzoom: 14,
  };

  const skyLayer = {
    id: "sky",
    type: "sky",
    paint: {
      "sky-type": "atmosphere",
      "sky-atmosphere-sun": [0.0, 0.0],
      "sky-atmosphere-sun-intensity": 15,
    },
  };

  style.layers = [...baseStyle.layers, skyLayer];
  return style;
}

const geologyLayerDefs = function (colors = {}, patterns = {}) {
  console.log(colors, patterns);
  return [
    {
      id: "unit",
      source: "geology",
      "source-layer": "bedrock",
      type: "fill",
      minzoom: 11,
      paint: {
        "fill-pattern": ["concat", ["get", "unit_id"], "_fill"],
        "fill-opacity": 0.9,
      },
    },
    {
      id: "unit-lowzoom",
      source: "geology",
      "source-layer": "bedrock",
      type: "fill",
      maxzoom: 10,
      paint: {
        "fill-color": ["get", ["get", "unit_id"], ["literal", colors]],
        "fill-opacity": 0.5,
      },
    },
    {
      id: "bedrock-contact",
      source: "geology",
      "source-layer": "contact",
      type: "line",
      layout: {
        "line-cap": "round",
      },
      paint: {
        "line-color": "#000000",
        "line-width": [
          "interpolate",
          ["exponential", 2],
          ["zoom"],
          10,
          ["*", 3, ["^", 2, -6]],
          24,
          ["*", 3, ["^", 2, 8]],
        ],
      },
      filter: [
        "all",
        ["!=", "surficial", ["get", "type"]],
        ["!=", "thrust-fault", ["get", "type"]],
      ],
    },
    {
      id: "thrust-fault",
      source: "geology",
      "source-layer": "contact",
      type: "line",
      layout: {
        "line-cap": "round",
      },
      paint: {
        "line-color": "#000000",
        "line-width": [
          "interpolate",
          ["exponential", 2],
          ["zoom"],
          10,
          ["*", 5, ["^", 2, -6]],
          24,
          ["*", 5, ["^", 2, 8]],
        ],
      },
      filter: ["==", "thrust-fault", ["get", "type"]],
    },
    ...createLineSymbolLayers(),
    {
      id: "surficial-contact",
      source: "geology",
      "source-layer": "contact",
      type: "line",
      layout: {
        "line-cap": "round",
      },
      paint: {
        "line-color": "#ffbe17",
      },
      filter: ["==", "surficial", ["get", "type"]],
    },
    {
      id: "surface",
      source: "geology",
      "source-layer": "surficial",
      type: "fill",
      paint: {
        "fill-color": ["get", ["get", "unit_id"], ["literal", colors]],
        //"fill-pattern": ["get", ["get", "unit_id"], ["literal", patterns]],
        "fill-opacity": 0.5,
      },
    },
    {
      id: "watercourse",
      source: "geology",
      "source-layer": "line",
      type: "line",
      paint: {
        "line-color": "#3574AC",
        "line-width": 1,
      },
      filter: ["==", "watercourse", ["get", "type"]],
    },
    {
      id: "line",
      source: "geology",
      "source-layer": "line",
      type: "line",
      paint: {
        "line-color": "#cccccc",
      },
      filter: ["!=", "watercourse", ["get", "type"]],
    },
  ];
};

function geologyLayerIDs() {
  const defs = geologyLayerDefs();
  return defs.map((d) => d.id);
}

const createGeologyStyle = function (
  baseStyle,
  polygonTypes,
  hostName = "http://localhost:3006"
) {
  const colors = {};
  const patterns = {};
  for (let d of Array.from(polygonTypes)) {
    colors[d.id] = d.color;
    patterns[d.id] = d.symbol ?? null;
  }

  const geologyLayers = geologyLayerDefs(colors, patterns);

  let style = baseStyle;
  style.sources.geology = createGeologySource(hostName);
  style.layers = [...baseStyle.layers, ...geologyLayers];
  return style;
};

async function getMapboxStyle(url, { access_token }) {
  const res = await axios.get(url, { params: { access_token } });
  return res.data;
}

export {
  createGeologyStyle,
  createBasicStyle,
  createGeologySource,
  getMapboxStyle,
  geologyLayerIDs,
};
