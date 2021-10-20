/**
 * Create a map style for StraboSpot features. This is lifted directly from the
 * StraboSpot codebase, https://github.com/StraboSpot/StraboSpot-Mobile/blob/master/src/modules/maps/useMapSymbology.js
 */
import { getIconImageExt } from "./icon-image";

const pointLayers = (opts: { showAll?: boolean } = {}) => {
  const { showAll = false } = opts;
  const isShowSpotLabelsOn = false;

  // Get the rotation of the symbol, either strike, trend or failing both, 0
  const getIconRotation = () => {
    return [
      "case",
      ["has", "strike", ["get", "orientation"]],
      ["get", "strike", ["get", "orientation"]],
      [
        "case",
        ["has", "dip_direction", ["get", "orientation"]],
        ["%", ["-", ["get", "dip_direction", ["get", "orientation"]], 90], 360],
        [
          "case",
          ["has", "trend", ["get", "orientation"]],
          ["get", "trend", ["get", "orientation"]],
          0,
        ],
      ],
    ];
  };

  // Get the label for the point symbol, either dip, plunge or failing both, the Spot name
  const getPointLabel = ({ showNames = false } = {}) => {
    return [
      "case",
      ["has", "orientation"],
      [
        "case",
        ["has", "plunge", ["get", "orientation"]],
        ["get", "plunge", ["get", "orientation"]],
        [
          "case",
          ["has", "dip", ["get", "orientation"]],
          ["get", "dip", ["get", "orientation"]],
          ["get", "name"],
        ],
      ],
      showNames ? ["get", "name"] : "",
    ];

    // Does not work on iOS - iOS doesn't build if there is more than 1 condition and a fallback in a case expression
    /*return ['case', ['has', 'orientation'],
     ['case',
     ['has', 'dip', ['get', 'orientation']], ['get', 'dip', ['get', 'orientation']],
     ['has', 'plunge', ['get', 'orientation']], ['get', 'plunge', ['get', 'orientation']],
     ['get', 'name'],
     ],
     ['get', 'name'],
     ];*/
  };

  // Get the label offset, which is further to the right if the symbol rotation is between 60-120 or 240-300
  const getLabelOffset = () => {
    return [
      "case",
      ["has", "orientation"],
      // Variable bindings
      [
        "let",
        "rotation",
        [
          "case",
          ["has", "strike", ["get", "orientation"]],
          ["get", "strike", ["get", "orientation"]],
          [
            "case",
            ["has", "dip_direction", ["get", "orientation"]],
            [
              "%",
              ["-", ["get", "dip_direction", ["get", "orientation"]], 90],
              360,
            ],
            [
              "case",
              ["has", "trend", ["get", "orientation"]],
              ["get", "trend", ["get", "orientation"]],
              0,
            ],
          ],
        ],

        // Output
        [
          "case",
          // Symbol rotation between 60-120 or 240-300
          [
            "any",
            [
              "all",
              [">=", ["var", "rotation"], 60],
              ["<=", ["var", "rotation"], 120],
            ],
            [
              "all",
              [">=", ["var", "rotation"], 240],
              ["<=", ["var", "rotation"], 300],
            ],
          ],
          ["literal", [2, 0]], // Need to specifiy 'literal' to return an array in expressions
          // Default
          ["literal", [0.75, 0]],
        ],
      ],
      ["literal", [0.75, 0]],
    ];
  };

  const baseLayout = {
    "text-anchor": "left",
    "text-offset": getLabelOffset(),
    "text-field": isShowSpotLabelsOn ? getPointLabel() : "",
    "icon-image": getIconImageExt(),
    "icon-rotate": getIconRotation(),
    "icon-rotation-alignment": "map",
    "icon-size": 0.15,
    "symbol-spacing": 1,
    "icon-padding": 0,
  };

  const allMeasurementsLayer = {
    id: "measurements",
    type: "symbol",
    source: "measurements",
    layout: {
      ...baseLayout,
      "text-ignore-placement": true, // Need to be able to stack symbols at same location
      "icon-allow-overlap": true, // Need to be able to stack symbols at same location
      "icon-ignore-placement": true, // Need to be able to stack symbols at same location
    },
  };

  if (showAll) {
    return [allMeasurementsLayer];
  }

  const symbolLayers = [0, 1, 2].map((d) => {
    return {
      id: `measurements_${d}`,
      type: "symbol",
      source: `measurements_${d}`,
      layout: baseLayout,
    };
  });

  return symbolLayers;
};

export { pointLayers };
