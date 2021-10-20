import { loadImage } from "../utils";
import pointSymbols from "./symbols/*.png";
import { pointLayers } from "./symbol-layer";
import axios from "axios";

async function measurementsSource(sourceURL) {
  const measurementsURL = sourceURL + "/strabo/measurements";
  const measurements = await axios.get(measurementsURL);
  const features = measurements.data?.features; //.map(preprocessMeasurement);

  function createMeasurementsSource(features, index = null) {
    if (index != null) {
      features = features.filter((d) => d.properties.spot_index == index);
    }
    return {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features,
      },
    };
  }

  return {
    measurements: createMeasurementsSource(features),
    measurements_0: createMeasurementsSource(features, 0),
    measurements_1: createMeasurementsSource(features, 1),
    measurements_2: createMeasurementsSource(features, 2),
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
        "circle-radius": [
          "case",
          ["has", "tag_color"],
          ["case", ["==", ["get", "tag_color"], "#000000"], 1.5, 3],
          1.5,
        ],
      },
    },
    ...pointLayers(),
  ];
}

function measurementLayerIDs() {
  return measurementsLayers().map((layer) => layer.id);
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

export {
  measurementsSource,
  measurementsLayers,
  setupPointSymbols,
  measurementLayerIDs,
};
