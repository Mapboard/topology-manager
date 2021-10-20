import { loadImage } from "../utils";
import pointSymbols from "./symbols/*.png";
import { pointLayers } from "./symbol-layer";

async function measurementsSource(sourceURL) {
  const measurementsURL = sourceURL + "/strabo/measurements";
  //const measurements = await axios.get(sourceURL + "/strabo/measurements");
  //const features = measurements.data?.features.map(preprocessMeasurement);

  return {
    measurements: {
      type: "geojson",
      data: measurementsURL, //{ type: "FeatureCollection", features },
    },
    spots: {
      type: "geojson",
      data: sourceURL + "/strabo/spots",
    },
  };
}

function measurementsLayers() {
  /** Spot and measurement symbol layers to add to the map */
  return [
    {
      source: "spots",
      id: "spots",
      type: "circle",
      paint: {
        "circle-color": [
          "case",
          ["has", "tag_color"],
          ["get", "tag_color"],
          ["get", "circleColor", ["get", "symbology"]],
        ],
        "circle-opacity": 0.8,
        //"circle-stroke-color": "#9993a1",
        //"circle-stroke-width": 0.5,
        "circle-radius": 3,
      },
    },
    ...pointLayers(),
  ];
}

async function setupPointSymbols(map) {
  /** Load and prepare all symbols for measurements */
  return Promise.all(
    Object.keys(pointSymbols).map(async function (symbol) {
      console.log(pointSymbols[symbol]);
      const image = await loadImage(map, pointSymbols[symbol]);
      if (map.hasImage(symbol)) return;
      console.log(image);
      map.addImage(symbol, image, { sdf: false, pixelRatio: 3 });
    })
  );
}

export { measurementsSource, measurementsLayers, setupPointSymbols };
