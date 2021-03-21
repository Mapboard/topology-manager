import axios from "axios";

const createGeologySource = (host) => ({
  type: "vector",

  tiles: [`${host}/live-tiles/map-data/{z}/{x}/{y}.pbf`],

  maxzoom: 15,
  minzoom: 5,
});

const createStyle = function (
  baseStyle,
  polygonTypes,
  hostName = "http://localhost:3006"
) {
  const colors = {};
  for (let d of Array.from(polygonTypes)) {
    colors[d.id] = d.color;
  }

  const geologyLayers = [
    {
      id: "unit",
      source: "geology",
      "source-layer": "bedrock",
      type: "fill",
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
      //filter: ["!", ["match", "surficial", ["get", "type"]]]
    },
    {
      id: "surface",
      source: "geology",
      "source-layer": "surficial",
      type: "fill",
      paint: {
        "fill-color": ["get", ["get", "unit_id"], ["literal", colors]],
      },
    },
    // {
    //   "id": "surficial-contact",
    //   "source": "geology",
    //   "source-layer": "contact",
    //   "type": "line",
    //   "paint": {
    //     "line-color": "#ffbe17"
    //   }
    //   filter: ["match", "surficial", ["get", "type"]]
    // }
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

  const style = { ...baseStyle };

  style.sources.geology = createGeologySource(hostName);

  style.layers = [...baseStyle.layers, ...geologyLayers];

  //style.geologyLayers = geologyLayers

  return style;
};

async function getStyle({ access_token }) {
  const res = await axios.get(
    "https://api.mapbox.com/styles/v1/jczaplewski/cklb8aopu2cnv18mpxwfn7c9n",
    { params: { access_token } }
  );
  return res.data;
}

module.exports = { createStyle, createGeologySource, getStyle };
