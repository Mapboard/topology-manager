import { loadImage } from "../utils";
import pointSymbols from "./symbols/*.png";

function measurementsSource(sourceURL) {
  return {
    measurements: {
      type: "geojson",
      data: sourceURL + "/measurements",
    },
  };
}

function measurementsLayers() {
  return [
    {
      source: "measurements",
      id: "measurements",
      type: "circle",
      paint: {
        "circle-color": ["get", "circleColor", ["get", "symbology"]],
        "circle-stroke-color": "#9993a1",
        "circle-stroke-width": 1,
        "circle-radius": 3,
      },
    },
  ];
}

async function setupPointSymbols(map) {
  console.log(pointSymbols);
  return Promise.all(
    Object.keys(pointSymbols).map(async function (symbol) {
      const image = await loadImage(map, pointSymbols[symbol]);
      if (map.hasImage(symbol)) return;
      map.addImage(symbol, image, { sdf: true, pixelRatio: 3 });
    })
  );
}

export { measurementsSource, measurementsLayers, setupPointSymbols };
