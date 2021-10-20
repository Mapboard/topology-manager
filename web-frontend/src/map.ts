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
import { ModalPanel, JSONView } from "@macrostrat/ui-components";
import {
  LayerDescription,
  baseLayers,
  BaseLayerSwitcher,
} from "./layer-switcher";
import { Spot } from "./spots";

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

interface MapOptions {
  onClickSpot?: Function;
}

async function initializeMap(el: HTMLElement, options: MapOptions = {}) {
  //const style = createStyle(polygonTypes);
  const { onClickSpot } = options;

  const map = new mapboxgl.Map({
    container: el,
    style: baseLayers[0].url,
    hash: true,
    center: [16.1987, -24.2254],
    zoom: 10,
    crossSourceCollisions: false,
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
    setupPointInteractivity(map, onClickSpot);
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

  map.on("click", (e) => {
    // Set `bbox` as 5px reactangle area around clicked point.
    const bbox = [
      [e.point.x - 5, e.point.y - 5],
      [e.point.x + 5, e.point.y + 5],
    ];
    // Find features intersecting the bounding box.
    const selectedFeatures = map.queryRenderedFeatures(bbox, {
      layers: ["unit"],
    });
    console.log(selectedFeatures);
  });

  map.on("mouseenter", "spots", function (e) {
    map.getCanvas().style.cursor = "pointer";
  });

  map.on("mouseleave", "spots", function () {
    map.getCanvas().style.cursor = "";
    //popup.remove();
  });

  map.on("click", "spots", function (e) {
    onClick?.(e.features);
  });
}

interface MapState {
  enableGeology: boolean;
  activeLayer: LayerDescription;
  activeSpots: Object[] | null;
}

type SetActiveLayer = { type: "set-active-layer"; layer: LayerDescription };
type ToggleGeology = { type: "toggle-geology" };
type SetActiveSpot = { type: "set-active-spots"; spots: Object[] | null };

type MapAction = SetActiveLayer | ToggleGeology | SetActiveSpot;

function mapReducer(state: MapState, action: MapAction) {
  switch (action.type) {
    case "set-active-layer":
      return { ...state, activeLayer: action.layer };
    case "toggle-geology":
      return { ...state, enableGeology: !state.enableGeology };
    case "set-active-spots":
      return { ...state, activeSpots: action.spots };
    default:
      return state;
  }
}

const defaultState: MapState = {
  enableGeology: true,
  activeLayer: baseLayers[0],
  activeSpots: null,
};

export function MapComponent() {
  const ref = useRef<HTMLElement>();

  const [state, dispatch] = useReducer(mapReducer, defaultState);

  const mapRef = useRef<Map>();

  useEffect(() => {
    if (ref.current == null) return;
    initializeMap(ref.current, {
      onClickSpot(features) {
        dispatch({ type: "set-active-spots", spots: features });
      },
    }).then((mapObj) => {
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

  const isOpen = state.activeSpots != null;

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
    h("div.map-info", [
      h(InfoModal, {
        isOpen,
        onClose() {
          dispatch({ type: "set-active-spots", spots: null });
        },
        spots: state.activeSpots,
      }),
    ]),
  ]);
}

function InfoModal({ isOpen, onClose, spots = [] }) {
  if (!isOpen) return null;

  return h(
    ModalPanel,
    {
      title: "Spots",
      onClose,
    },
    spots.map((spot) => {
      return h(Spot, { data: spot.properties });
    })
  );
}
