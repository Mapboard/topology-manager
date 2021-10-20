import { createGeologySource, geologyLayerIDs } from "./style/geology-layers";
import { GeologyStyler } from "./style";
import io from "socket.io-client";
import { debounce } from "underscore";
import mapboxgl, { Map } from "mapbox-gl";
import mbxUtils from "mapbox-gl-utils";
import "mapbox-gl/dist/mapbox-gl.css";
import { useEffect, useRef, Dispatch, Ref } from "react";
import h from "@macrostrat/hyper";
import axios from "axios";
import { baseLayers } from "./style";
import { MapState, MapAction } from "../actions";
import { sourceURL } from "../config";

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

async function reloadStyle(map: Map, styler: GeologyStyler, baseLayer: string) {
  const style = await styler.createStyle(map, baseLayer);
  map.setStyle(style);
  if (map.getSource("mapbox-dem") == null) return;
  map.setTerrain({ source: "mapbox-dem", exaggeration: 1.0 });
}

async function initializeMap(
  el: HTMLElement,
  styler: GeologyStyler,
  options: MapOptions = {}
): Promise<Map> {
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
    await reloadStyle(map, styler, baseLayers[0].url);
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

function useLayerVisibility(
  mapRef: Ref<Map>,
  layers: string[],
  enabled: boolean
) {
  useEffect(() => {
    const map = mapRef.current;
    if (map?.style == null) return;
    for (const lyr of layers) {
      map.setLayoutProperty(lyr, "visibility", enabled ? "visible" : "none");
    }
  }, [mapRef, layers, enabled]);
}

export function MapComponent({
  state,
  dispatch,
}: {
  state: MapState;
  dispatch: Dispatch<MapAction>;
}) {
  const ref = useRef<HTMLElement>();

  const mapRef = useRef<Map>();
  const stylerRef = useRef<GeologyStyler>(
    new GeologyStyler(sourceURL, {
      enableGeology: true,
      enableMeasurements: true,
      showAllMeasurements: state.showAllSpots,
    })
  );

  useEffect(() => {
    if (ref.current == null) return;
    initializeMap(ref.current, stylerRef.current, {
      onClickSpot(features) {
        dispatch({ type: "set-active-spots", spots: features });
      },
    }).then((mapObj) => {
      mapRef.current = mapObj;
    });

    return () => mapRef.current.remove();
  }, [ref]);

  useLayerVisibility(
    mapRef,
    stylerRef.current.measurementsStyler.layerIDs(),
    state.enableSpots
  );
  useLayerVisibility(mapRef, geologyLayerIDs(), state.enableGeology);

  useEffect(() => {
    if (mapRef.current == null) return;
    stylerRef.current = new GeologyStyler(sourceURL, {
      enableGeology: true,
      enableMeasurements: true,
      showAllMeasurements: state.showAllSpots,
    });
    reloadStyle(mapRef.current, stylerRef.current, state.activeLayer.url);
  }, [mapRef, state.showAllSpots]);

  // Base layer management
  useEffect(() => {
    if (mapRef.current == null) return;
    reloadStyle(mapRef.current, stylerRef.current, state.activeLayer.url);
  }, [mapRef, state.activeLayer]);

  return h("div.map", { ref });
}
