import { loadImage } from "../utils";
import pointSymbols from "./symbols/*.png";
import { pointLayers } from "./symbol-layer";
import axios from "axios";

interface PlanarOrientationData {
  dip: number;
  strike: number;
  foliation_type: string;
  foliation_defined_by?: string;
  type: string;
}

interface LinearOrientationData {
  feature_type: string;
  trend: number;
  plunge: number;
  rake_calculated?: boolean;
}

type OrientationData = PlanarOrientationData | LinearOrientationData;

interface MeasurementData {
  orientation: OrientationData;
}

function getOrientationSymbolName(o: OrientationData) {
  /** Get a symbol for a measurement based on its orientation.
   * This straightforward construction is more or less
   * equivalent to the logic in the Mapbox GL style specification above.
   */
  let { feature_type } = o;
  const symbol_orientation = o.dip ?? o.plunge ?? 0;

  if (["fault", "fracture", "vein"].includes(feature_type)) {
    return feature_type;
  }

  if (o.facing == "overturned" && feature_type == "bedding") {
    return "bedding-overturned";
  }

  if (
    symbol_orientation == 0 &&
    (feature_type == "bedding" || feature_type == "foliation")
  ) {
    return `${feature_type}_horizontal`;
  }
  if (
    symbol_orientation > 0 &&
    symbol_orientation <= 90 &&
    ["bedding", "contact", "foliation", "shear_zone"].includes(feature_type)
  ) {
    if (symbol_orientation == 90) {
      return `${feature_type}_vertical`;
    }
    return `${feature_type}_inclined`;
  }

  if (o.type == "linear_orientation") {
    return "lineation_general";
  }

  return "default_point";
}

function preprocessMeasurement(measurement: MeasurementData) {
  /**
   * Prepare a measurement for use in the map
   * @param {Object}
   */

  console.log(measurement.properties);

  measurement.properties.symbology ??= {};
  measurement.properties.symbol_name = getOrientationSymbolName(
    measurement.properties.orientation
  );

  return measurement;
}

async function measurementsSource(sourceURL) {
  const measurementsURL = sourceURL + "/strabo/measurements";
  //const measurements = await axios.get(sourceURL + "/strabo/measurements");
  //const features = measurements.data?.features.map(preprocessMeasurement);

  return {
    measurements: {
      type: "geojson",
      data: measurementsURL, //{ type: "FeatureCollection", features },
    },
    spots: {
      type: "geojson",
      data: sourceURL + "/strabo/spots",
    },
  };
}

function measurementsLayers() {
  /** Spot and measurement symbol layers to add to the map */
  return [
    {
      source: "spots",
      id: "spots",
      type: "circle",
      paint: {
        "circle-color": ["get", "circleColor", ["get", "symbology"]],
        //"circle-stroke-color": "#9993a1",
        //"circle-stroke-width": 0.5,
        "circle-radius": 3,
      },
    },
    ...pointLayers(),
  ];
}

async function setupPointSymbols(map) {
  /** Load and prepare all symbols for measurements */
  return Promise.all(
    Object.keys(pointSymbols).map(async function (symbol) {
      console.log(pointSymbols[symbol]);
      const image = await loadImage(map, pointSymbols[symbol]);
      if (map.hasImage(symbol)) return;
      console.log(image);
      map.addImage(symbol, image, { sdf: false, pixelRatio: 3 });
    })
  );
}

export { measurementsSource, measurementsLayers, setupPointSymbols };
