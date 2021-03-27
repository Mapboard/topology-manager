import "babel-polyfill";
import { createStyle, createGeologySource, getMapboxStyle } from "./map-style";
import io from "socket.io-client";
import { get } from "axios";
import { debounce } from "underscore";
import mapboxgl, { Map } from "mapbox-gl";
import mbxUtils from "mapbox-gl-utils";
import "mapbox-gl/dist/mapbox-gl.css";
import { useEffect, useRef, useState } from "react";
import h from "@macrostrat/hyper";
import { ButtonGroup, Button } from "@blueprintjs/core";
import "@blueprintjs/core/lib/css/blueprint.css";

mapboxgl.accessToken = process.env.MAPBOX_TOKEN;

const t1 = "mapbox://styles/jczaplewski/ckml6tqii4gvn17o073kujk75";

const satellite = "https://api.mapbox.com/styles/v1/mapbox/satellite-v9";
const terrain = t1.replace(
  "mapbox://styles",
  "https://api.mapbox.com/styles/v1"
);

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

async function createMapStyle(url) {
  const { data: polygonTypes } = await get(
    "http://localhost:3006/polygon/types"
  );
  const baseStyle = await getMapboxStyle(url, {
    access_token: mapboxgl.accessToken,
  });
  return createStyle(baseStyle, polygonTypes);
}

async function initializeMap(el: HTMLElement) {
  //const style = createStyle(polygonTypes);
  const style = await createMapStyle(baseLayers[0].url);

  const map = new mapboxgl.Map({
    container: el,
    style,
    //style: "mapbox://styles/jczaplewski/cklb8aopu2cnv18mpxwfn7c9n",
    hash: true,
    center: [16.1987, -24.2254],
    zoom: 10,
  });

  //map.setStyle("mapbox://styles/jczaplewski/cklb8aopu2cnv18mpxwfn7c9n");

  map.on("style.load", function () {
    map.addSource("mapbox-dem", {
      type: "raster-dem",
      url: "mapbox://mapbox.mapbox-terrain-dem-v1",
      tileSize: 512,
      maxzoom: 14,
    });
    // add the DEM source as a terrain layer with exaggerated height
    map.setTerrain({ source: "mapbox-dem", exaggeration: 1.5 });

    // add a sky layer that will show when the map is highly pitched
    map.addLayer({
      id: "sky",
      type: "sky",
      paint: {
        "sky-type": "atmosphere",
        "sky-atmosphere-sun": [0.0, 0.0],
        "sky-atmosphere-sun-intensity": 15,
      },
    });
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
    url: "https://api.mapbox.com/styles/v1/mapbox/satellite-v9",
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
    if (map == null) return;
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
    createMapStyle(activeLayer.url).then((style) => map.setStyle(style));
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
