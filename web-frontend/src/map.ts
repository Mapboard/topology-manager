import "babel-polyfill";
import {
  createGeologySource,
  geologyLayerIDs,
} from "./map-style/geology-layers";
import { createMapStyle, terrain } from "./map-style";
import io from "socket.io-client";
import { debounce } from "underscore";
import mapboxgl, { Map } from "mapbox-gl";
import mbxUtils from "mapbox-gl-utils";
import "mapbox-gl/dist/mapbox-gl.css";
import { useEffect, useRef, useState } from "react";
import h from "@macrostrat/hyper";
import { ButtonGroup, Button } from "@blueprintjs/core";
import axios from "axios";
import "@blueprintjs/core/lib/css/blueprint.css";

mapboxgl.accessToken = process.env.MAPBOX_TOKEN;

const sourceURL = process.env.GEOLOGIC_MAP_ADDRESS || "http://localhost:3006";

let ix = 0;
let oldID = "geology";
function reloadGeologySource(map) {
  ix += 1;
  const newID = `geology-${ix}`;
  map.addSource(newID, createGeologySource(sourceURL));
  map.U.setLayerSource(geologyLayerIDs(), newID);
  map.removeSource(oldID);
  oldID = newID;
}

async function fitBounds(map) {
  const res = await axios.get(sourceURL + "/meta");
  const bounds = res.data?.projectBounds;
  if (bounds != null) {
    map.fitBounds(
      [
        [bounds[0], bounds[1]],
        [bounds[2], bounds[3]],
      ],
      { duration: 0 }
    );
  }
}

const sourceURI = new URL(sourceURL);
const hostName = sourceURI.protocol + "//" + sourceURI.hostname;

async function initializeMap(el: HTMLElement) {
  //const style = createStyle(polygonTypes);

  const map = new mapboxgl.Map({
    container: el,
    style: baseLayers[0].url,
    hash: true,
    center: [16.1987, -24.2254],
    zoom: 10,
  });

  fitBounds(map);

  //map.setStyle("mapbox://styles/jczaplewski/cklb8aopu2cnv18mpxwfn7c9n");
  map.on("load", async function () {
    const style = await createMapStyle(map, baseLayers[0].url, sourceURL, true);
    map.setStyle(style);
    if (map.getSource("mapbox-dem") == null) return;
    map.setTerrain({ source: "mapbox-dem", exaggeration: 1.0 });
  });

  map.on("style.load", async function () {
    console.log("Reloaded style");
    if (map.getSource("mapbox-dem") == null) return;
    map.setTerrain({ source: "mapbox-dem", exaggeration: 1.0 });
  });

  mbxUtils.init(map, mapboxgl);

  const _ = function () {
    console.log("Reloading map");
    return reloadGeologySource(map);
  };
  const reloadMap = debounce(_, 500);

  const socket = io(hostName, {
    path: sourceURI.pathname + "/socket.io",
  });
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

function BaseLayerSwitcher({ activeLayer, onSetLayer }) {
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
    console.log(enableGeology);
    for (const lyr of geologyLayerIDs()) {
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
    createMapStyle(map, activeLayer.url, sourceURL).then((style) =>
      map.setStyle(style)
    );
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
