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
import { useEffect, useRef, useState, useReducer } from "react";
import h from "@macrostrat/hyper";
import { ButtonGroup, Button } from "@blueprintjs/core";
import axios from "axios";
import "@blueprintjs/core/lib/css/blueprint.css";
import {
  LayerDescription,
  baseLayers,
  BaseLayerSwitcher,
} from "./layer-switcher";

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
  const res = await axios.get(sourceURL + "/feature-server/meta");
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
    setupPointInteractivity(map);
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
    reconnectionAttempts: 5,
  });
  socket.on("topology", function (message) {
    console.log(message);
    return reloadMap();
  });

  return map;
}

function setupPointInteractivity(map: mapboxgl.Map, onClick?: Function) {
  var popup = new mapboxgl.Popup({
    closeButton: false,
    closeOnClick: false,
  });

  console.log("Setting up point interactivity");

  // map.on("mouseenter", "spots", function (e) {
  //   map.getCanvas().style.cursor = "pointer";
  //   // return;
  //   // var coordinates = e.features[0].geometry.coordinates.slice();
  //   // var description: string = e.features[0].properties.notes;
  //   // console.log(description);
  //   // if (description == null || description == "null") return;
  //   // // Change the cursor style as a UI indicator.
  //   // map.getCanvas().style.cursor = "pointer";
  //   // // Ensure that if the map is zoomed out such that multiple
  //   // // copies of the feature are visible, the popup appears
  //   // // over the copy being pointed to.
  //   // while (Math.abs(e.lngLat.lng - coordinates[0]) > 180) {
  //   //   coordinates[0] += e.lngLat.lng > coordinates[0] ? 360 : -360;
  //   // }

  //   // // Populate the popup and set its coordinates
  //   // // based on the feature found.
  //   // popup.setLngLat(coordinates).setHTML(description).addTo(map);
  // });

  // map.on("mouseleave", "spots", function () {
  //   map.getCanvas().style.cursor = "";
  //   //popup.remove();
  // });

  map.on("click", "spots", function (e) {
    onClick?.(e.features[0]);
  });
}

interface MapState {
  enableGeology: boolean;
  activeLayer: LayerDescription;
  activeSpot: Object | null;
}

type SetActiveLayer = { type: "set-active-layer"; layer: LayerDescription };
type ToggleGeology = { type: "toggle-geology" };
type SetActiveSpot = { type: "set-active-spot"; spot: Object | null };

type MapAction = SetActiveLayer | ToggleGeology | SetActiveSpot;

function mapReducer(state: MapState, action: MapAction) {
  switch (action.type) {
    case "set-active-layer":
      return { ...state, activeLayer: action.layer };
    case "toggle-geology":
      return { ...state, enableGeology: !state.enableGeology };
    case "set-active-spot":
      return { ...state, activeSpot: action.spot };
    default:
      return state;
  }
}

const defaultState: MapState = {
  enableGeology: true,
  activeLayer: baseLayers[0],
  activeSpot: null,
};

export function MapComponent() {
  const ref = useRef<HTMLElement>();

  const [state, dispatch] = useReducer(mapReducer, defaultState);

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
    for (const lyr of geologyLayerIDs()) {
      map.setLayoutProperty(
        lyr,
        "visibility",
        state.enableGeology ? "visible" : "none"
      );
    }
  }, [mapRef, state.enableGeology]);

  useEffect(() => {
    const map = mapRef.current;
    if (map == null) return;
    createMapStyle(map, state.activeLayer.url, sourceURL).then((style) => {
      map.setStyle(style);
    });
  }, [mapRef, state.activeLayer]);

  return h("div.map-area", [
    h("div.map", { ref }),
    h("div.map-controls", null, [
      h(
        Button,
        {
          active: state.enableGeology,
          onClick() {
            dispatch({ type: "toggle-geology" });
          },
        },
        "Geology"
      ),
      h(BaseLayerSwitcher, {
        activeLayer: state.activeLayer,
        onSetLayer(layer) {
          dispatch({ type: "set-active-layer", layer });
        },
      }),
    ]),
  ]);
}
