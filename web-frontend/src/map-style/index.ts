import {
  createGeologyStyle,
  createBasicStyle,
  createGeologySource,
  geologyLayerIDs,
  getMapboxStyle,
} from "./geology-layers";
import { createUnitFill } from "./pattern-fill";
import io from "socket.io-client";
import { get } from "axios";
import mapboxgl from "mapbox-gl";
import "mapbox-gl/dist/mapbox-gl.css";
import { lineSymbols } from "./symbol-layers";
import { measurementsSource, measurementsLayers } from "./point-features";
import "@blueprintjs/core/lib/css/blueprint.css";

const vizBaseURL = "//visualization-assets.s3.amazonaws.com";
const patternBaseURL = vizBaseURL + "/geologic-patterns/png";
const lineSymbolsURL = vizBaseURL + "/geologic-line-symbols/png";

const satellite = "mapbox://styles/mapbox/satellite-v9";
const terrain = "mapbox://styles/jczaplewski/ckml6tqii4gvn17o073kujk75";

async function loadImage(map, url: string) {
  return new Promise((resolve, reject) => {
    map.loadImage(url, function (err, image) {
      // Throw an error if something went wrong
      if (err) reject(err);
      // Declare the image
      resolve(image);
    });
  });
}

async function setupLineSymbols(map) {
  return Promise.all(
    lineSymbols.map(async function (symbol) {
      const image = await loadImage(map, lineSymbolsURL + `/${symbol}.png`);
      if (map.hasImage(symbol)) return;
      map.addImage(symbol, image, { sdf: true, pixelRatio: 3 });
    })
  );
}

async function setupStyleImages(map, polygonTypes) {
  return Promise.all(
    Array.from(polygonTypes).map(async function (type: any) {
      const { symbol, id } = type;
      const uid = id + "_fill";
      if (map.hasImage(uid)) return;
      const url = symbol == null ? null : patternBaseURL + `/${symbol}.png`;
      let { color } = type;

      // Handle special case where color is not a correct hex color
      if (color.length == 6 && !color.startsWith("#")) {
        color = "#" + color;
      }

      console.log(color);

      const img = await createUnitFill({
        patternURL: url,
        color: color,
        patternColor: type.symbol_color,
      });

      map.addImage(uid, img, { sdf: false, pixelRatio: 12 });
    })
  );
}

async function createMapStyle(map, url, sourceURL, enableGeology = true) {
  const { data: polygonTypes } = await get(
    sourceURL + "/feature-server/polygon/types"
  );
  const baseURL = url.replace(
    "mapbox://styles",
    "https://api.mapbox.com/styles/v1"
  );
  let baseStyle = await getMapboxStyle(baseURL, {
    access_token: mapboxgl.accessToken,
  });
  baseStyle = createBasicStyle(baseStyle);
  if (!enableGeology) return baseStyle;
  await setupLineSymbols(map);
  await setupStyleImages(map, polygonTypes);
  let geologyStyle = createGeologyStyle(baseStyle, polygonTypes, sourceURL);

  // Should be conditional on whether measurements are enabled
  geologyStyle.sources = {
    ...geologyStyle.sources,
    ...measurementsSource(sourceURL),
  };

  geologyStyle.layers = [...geologyStyle.layers, ...measurementsLayers()];

  return geologyStyle;
}

export { createMapStyle, createGeologySource, terrain };
