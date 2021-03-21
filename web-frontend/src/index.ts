/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
import "babel-polyfill";
import { createStyle, createGeologySource } from "./map-style";
import io from "socket.io-client";
import { get } from "axios";
import { debounce } from "underscore";
import mbxUtils from "mapbox-gl-utils";

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
  const style = createStyle(polygonTypes);

  const map = new mapboxgl.Map({
    container: "map",
    style,
    hash: true,
    center: [16.1987, -24.2254],
    zoom: 10,
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
