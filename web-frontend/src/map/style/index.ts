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
import { setupPointSymbols, MeasurementStyler } from "./point-features";
import { loadImage } from "./utils";

export interface LayerDescription {
  id: string;
  name: string;
  url: string;
}

export const baseLayers: LayerDescription[] = [
  {
    id: "satellite",
    name: "Satellite",
    url: "mapbox://styles/mapbox/satellite-v9",
  },
  {
    id: "hillshade",
    name: "Hillshade",
    url: "mapbox://styles/jczaplewski/ckml6tqii4gvn17o073kujk75",
  },
];

const vizBaseURL = "//visualization-assets.s3.amazonaws.com";
const patternBaseURL = vizBaseURL + "/geologic-patterns/png";
const lineSymbolsURL = vizBaseURL + "/geologic-line-symbols/png";

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
      if (map.style != null && map.hasImage(uid)) return;
      const url = symbol == null ? null : patternBaseURL + `/${symbol}.png`;
      let { color } = type;

      // Handle special case where color is not a correct hex color
      if (color.length == 6 && !color.startsWith("#")) {
        color = "#" + color;
      }

      const img = await createUnitFill({
        patternURL: url,
        color: color,
        patternColor: type.symbol_color,
      });

      map.addImage(uid, img, { sdf: false, pixelRatio: 12 });
    })
  );
}

interface GeologyStylerOptions {
  enableGeology: boolean;
  enableMeasurements: boolean;
  showAllMeasurements: boolean;
}
class GeologyStyler {
  opts: GeologyStylerOptions;
  sourceURL: string;
  measurementsStyler: MeasurementStyler;
  constructor(sourceURL: string, options: Partial<GeologyStylerOptions> = {}) {
    this.sourceURL = sourceURL;
    const {
      enableGeology = true,
      enableMeasurements = true,
      showAllMeasurements = false,
    } = options;
    this.opts = { enableGeology, enableMeasurements };
    this.measurementsStyler = new MeasurementStyler(sourceURL, {
      showAll: showAllMeasurements,
    });
  }

  async createStyle(map: mapboxgl.Map, baseStyleURL: string) {
    const { data: polygonTypes } = await get(
      this.sourceURL + "/feature-server/polygon/types"
    );
    const baseURL = baseStyleURL.replace(
      "mapbox://styles",
      "https://api.mapbox.com/styles/v1"
    );
    let baseStyle = await getMapboxStyle(baseURL, {
      access_token: mapboxgl.accessToken,
    });
    baseStyle = createBasicStyle(baseStyle);
    if (!this.opts.enableGeology) return baseStyle;
    await Promise.all([
      setupLineSymbols(map),
      setupStyleImages(map, polygonTypes),
      setupPointSymbols(map),
    ]);

    let geologyStyle = createGeologyStyle(
      baseStyle,
      polygonTypes,
      this.sourceURL
    );

    geologyStyle.sources = {
      ...geologyStyle.sources,
      ...(await this.measurementsStyler.sources()),
    };

    geologyStyle.layers = [
      ...geologyStyle.layers,
      ...this.measurementsStyler.layers(),
    ];
    return geologyStyle;
  }
}

export { GeologyStyler, createGeologySource };
