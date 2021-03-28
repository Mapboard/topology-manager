import "babel-polyfill";
import {
  createGeologyStyle,
  createGeologySource,
  getMapboxStyle,
} from "./map-style";
import io from "socket.io-client";
import { get } from "axios";
import { debounce } from "underscore";
import mapboxgl, { Map } from "mapbox-gl";
import mbxUtils from "mapbox-gl-utils";
import "mapbox-gl/dist/mapbox-gl.css";
import { useEffect, useRef, useState } from "react";
import h from "@macrostrat/hyper";
import { ButtonGroup, Button } from "@blueprintjs/core";
import { lineSymbols } from "./map-style/symbol-layers";
import "@blueprintjs/core/lib/css/blueprint.css";

mapboxgl.accessToken = process.env.MAPBOX_TOKEN;

const vizBaseURL = "//visualization-assets.s3.amazonaws.com";
const patternBaseURL = vizBaseURL + "/geologic-patterns/png";
const lineSymbolsURL = vizBaseURL + "/geologic-line-symbols/png";

const satellite = "mapbox://styles/mapbox/satellite-v9";
const terrain = "mapbox://styles/jczaplewski/ckml6tqii4gvn17o073kujk75";

const geologyLayerIDs = [
  "unit",
  "bedrock-contact",
  "surface",
  "surficial-contact",
  "watercourse",
  "line",
];

let ix = 0;
let oldID = "geology";
const reloadGeologySource = function (map) {
  ix += 1;
  const newID = `geology-${ix}`;
  map.addSource(newID, createGeologySource());
  map.U.setLayerSource(geologyLayerIDs, newID);
  map.removeSource(oldID);
  return (oldID = newID);
};

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
  const loadableImages = polygonTypes.filter((type) => {
    return type.symbol != null && !map.hasImage(type.symbol);
  });

  const symbols = new Set(loadableImages.map((d) => d.symbol));

  return Promise.all(
    Array.from(symbols).map(async function (symbol) {
      const image = await loadImage(map, patternBaseURL + `/${symbol}.png`);
      console.log(symbol + " loaded");
      map.addImage(symbol, image, { sdf: true, pixelRatio: 12 });
    })
  );
}

async function createMapStyle(map, url) {
  const { data: polygonTypes } = await get(
    "http://localhost:3006/polygon/types"
  );
  const baseURL = url.replace(
    "mapbox://styles",
    "https://api.mapbox.com/styles/v1"
  );
  const baseStyle = await getMapboxStyle(baseURL, {
    access_token: mapboxgl.accessToken,
  });
  await setupLineSymbols(map);
  await setupStyleImages(map, polygonTypes);
  return createGeologyStyle(baseStyle, polygonTypes);
}

async function initializeMap(el: HTMLElement) {
  //const style = createStyle(polygonTypes);
  const style = baseLayers[0].url;

  const map = new mapboxgl.Map({
    container: el,
    style,
    hash: true,
    center: [16.1987, -24.2254],
    zoom: 10,
  });

  //map.setStyle("mapbox://styles/jczaplewski/cklb8aopu2cnv18mpxwfn7c9n");

  map.on("load", async function () {
    const style = await createMapStyle(map, baseLayers[0].url);
    map.setStyle(style);
    map.setTerrain({ source: "mapbox-dem", exaggeration: 1.5 });
  });

  mbxUtils.init(map, mapboxgl);

  const _ = function () {
    console.log("Reloading map");
    return reloadGeologySource(map);
  };
  const reloadMap = debounce(_, 500);

  const socket = io();
  socket.on("topology", function (message) {
    console.log(message);
    return reloadMap();
  });

  return map;
}

const baseLayers = [
  {
    id: "satellite",
    name: "Satellite",
    url: "mapbox://styles/mapbox/satellite-v9",
  },
  {
    id: "hillshade",
    name: "Hillshade",
    url: terrain,
  },
];

function BaseLayerSwitcher({ layers, activeLayer, onSetLayer }) {
  return h(
    ButtonGroup,
    { vertical: true },
    baseLayers.map((d) => {
      return h(
        Button,
        {
          active: d == activeLayer,
          //disabled: d == activeLayer,
          onClick() {
            if (d == activeLayer) return;
            onSetLayer(d);
          },
        },
        d.name
      );
    })
  );
}

export function MapComponent() {
  const ref = useRef<HTMLElement>();

  const [enableGeology, setEnableGeology] = useState(true);
  const [activeLayer, setActiveLayer] = useState(baseLayers[0]);

  const mapRef = useRef<Map>();

  useEffect(() => {
    if (ref.current == null) return;
    initializeMap(ref.current).then((mapObj) => {
      mapRef.current = mapObj;
    });
    return () => mapRef.current.remove();
  }, [ref]);

  useEffect(() => {
    const map = mapRef.current;
    if (map?.style == null) return;
    for (const lyr of geologyLayerIDs) {
      map.setLayoutProperty(
        lyr,
        "visibility",
        enableGeology ? "visible" : "none"
      );
    }
  }, [mapRef, enableGeology]);

  useEffect(() => {
    const map = mapRef.current;
    if (map == null) return;
    createMapStyle(map, activeLayer.url).then((style) => map.setStyle(style));
  }, [mapRef, activeLayer]);

  return h("div.map-area", [
    h("div.map", { ref }),
    h("div.map-controls", null, [
      h(
        Button,
        {
          active: enableGeology,
          onClick() {
            setEnableGeology(!enableGeology);
          },
        },
        "Geology"
      ),
      h(BaseLayerSwitcher, {
        layers: baseLayers,
        activeLayer: activeLayer,
        onSetLayer(layer) {
          setActiveLayer(layer);
        },
      }),
    ]),
  ]);
}
