import mapboxgl from "mapbox-gl";
const mapboxToken = process.env.MAPBOX_TOKEN;
const sourceURL = process.env.GEOLOGIC_MAP_ADDRESS || "http://localhost:3006";
mapboxgl.accessToken = mapboxToken;

export { mapboxToken, sourceURL };
