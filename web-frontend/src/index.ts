import "babel-polyfill";
import { createStyle, createGeologySource } from "./map-style";
import io from "socket.io-client";
import { get } from "axios";
import { debounce } from "underscore";
import mapboxgl from "mapbox-gl";
import mbxUtils from "mapbox-gl-utils";
import "mapbox-gl/dist/mapbox-gl.css";
import "./main.styl";

mapboxgl.accessToken = process.env.MAPBOX_TOKEN;

let ix = 0;
let oldID = "geology";
const reloadGeologySource = function (map) {
  const layerIDs = [
    "unit",
    "bedrock-contact",
    "surface",
    "surficial-contact",
    "watercourse",
    "line",
  ];

  ix += 1;
  const newID = `geology-${ix}`;
  map.addSource(newID, createGeologySource());
  map.U.setLayerSource(layerIDs, newID);
  map.removeSource(oldID);
  return (oldID = newID);
};

(async function () {
  const { data: polygonTypes } = await get("/polygon/types");
  //const style = createStyle(polygonTypes);

  const map = new mapboxgl.Map({
    container: "map",
    style: "mapbox://styles/jczaplewski/cklb8aopu2cnv18mpxwfn7c9n",
    hash: true,
    center: [16.1987, -24.2254],
    zoom: 10,
  });

  map.on("load", function () {
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
  return socket.on("topology", function (message) {
    console.log(message);
    return reloadMap();
  });
})();
