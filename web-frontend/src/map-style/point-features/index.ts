import { loadImage } from "../utils";
import pointSymbols from "./symbols/*.png";
import { pointLayers } from "./symbol-layer";

function measurementsSource(sourceURL) {
  return {
    measurements: {
      type: "geojson",
      data: sourceURL + "/strabo/measurements",
    },
    spots: {
      type: "geojson",
      data: sourceURL + "/strabo/spots",
    },
  };
}

function measurementsLayers() {
  return [
    {
      source: "spots",
      id: "measurements",
      type: "circle",
      paint: {
        "circle-color": ["get", "circleColor", ["get", "symbology"]],
        "circle-stroke-color": "#9993a1",
        "circle-stroke-width": 1,
        "circle-radius": 3,
      },
    },
    ...pointLayers(),
  ];
}

async function setupPointSymbols(map) {
  return Promise.all(
    Object.keys(pointSymbols).map(async function (symbol) {
      const image = await loadImage(map, pointSymbols[symbol]);
      if (map.hasImage(symbol)) return;
      map.addImage(symbol, image, { sdf: false, pixelRatio: 3 });
    })
  );
}

export { measurementsSource, measurementsLayers, setupPointSymbols };
