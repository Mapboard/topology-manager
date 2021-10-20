/**
 * Create a map style for StraboSpot features. This is lifted directly from the
 * StraboSpot codebase, https://github.com/StraboSpot/StraboSpot-Mobile/blob/master/src/modules/maps/useMapSymbology.js
 */

const pointLayers = () => {
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
  const getPointLabel = () => {
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
      ["get", "name"],
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

  const getIconImage = () => {
    /** Get the image for a symbol using case-based logic. Taken as-is from StraboSpot codebase. Currently somewhat broken. */
    return [
      "case",
      ["has", "orientation"],
      // Variable bindings
      [
        "let",
        "symbol_orientation",
        [
          "case",
          ["has", "dip", ["get", "orientation"]],
          ["get", "dip", ["get", "orientation"]],
          [
            "case",
            ["has", "plunge", ["get", "orientation"]],
            ["get", "plunge", ["get", "orientation"]],
            0,
          ],
        ],
        [
          "let",
          "feature_type",
          ["get", "feature_type", ["get", "orientation"]],

          // Output
          [
            "case",
            // Case 1: Orientation has facing
            [
              "all",
              ["==", ["get", "facing", ["get", "orientation"]], "overturned"],
              ["any", ["==", ["var", "feature_type"], "bedding"]],
            ],
            [
              "concat",
              ["get", "feature_type", ["get", "orientation"]],
              "_overturned",
            ],
            [
              "case",
              // Case 2: Symbol orientation is 0 and feature type is bedding or foliation
              [
                "all",
                ["==", ["var", "symbol_orientation"], 0],
                [
                  "any",
                  ["==", ["var", "feature_type"], "bedding"],
                  ["==", ["var", "feature_type"], "foliation"],
                ],
              ],
              ["concat", ["var", "feature_type"], "_horizontal"],
              [
                "case",
                // Case 3: Symbol orientation between 0-90 and feature type is bedding, contact, foliation or shear zone
                [
                  "all",
                  [">", ["var", "symbol_orientation"], 0],
                  ["<", ["var", "symbol_orientation"], 90],
                  [
                    "any",
                    ["==", ["var", "feature_type"], "bedding"],
                    ["==", ["var", "feature_type"], "contact"],
                    ["==", ["var", "feature_type"], "foliation"],
                    ["==", ["var", "feature_type"], "shear_zone"],
                  ],
                ],
                ["concat", ["var", "feature_type"], "_inclined"],
                [
                  "case",
                  // Case 4: Symbol orientation is 90 and feature type is bedding, contact, foliation or shear zone
                  [
                    "all",
                    ["==", ["var", "symbol_orientation"], 90],
                    [
                      "any",
                      ["==", ["var", "feature_type"], "bedding"],
                      ["==", ["var", "feature_type"], "contact"],
                      ["==", ["var", "feature_type"], "foliation"],
                      ["==", ["var", "feature_type"], "shear_zone"],
                    ],
                  ],
                  ["concat", ["var", "feature_type"], "_vertical"],
                  [
                    "case",
                    // Case 5: Other features with no symbol orienation
                    [
                      "all",
                      ["has", "feature_type", ["get", "orientation"]],
                      [
                        "any",
                        ["==", ["var", "feature_type"], "fault"],
                        ["==", ["var", "feature_type"], "fracture"],
                        ["==", ["var", "feature_type"], "vein"],
                      ],
                    ],
                    ["get", "feature_type", ["get", "orientation"]],
                    [
                      "case",
                      // Defaults
                      [
                        "==",
                        ["get", "type", ["get", "orientation"]],
                        "linear_orientation",
                      ],
                      "lineation_general",
                      "default_point",
                    ],
                  ],
                ],
              ],
            ],
          ],
        ],
      ],
      "default_point",
    ];
  };

  function getIconImageExt() {
    /** Extension to Strabo-provided getIconImage that modifies the style tree to use programmatic definition of icon image if provided. */
    return [
      "case",
      ["has", "symbol_name"],
      ["get", "symbol_name"],
      getIconImage(),
    ];
  }

  const symbolLayers = [
    {
      id: "measurements",
      type: "symbol",
      source: "measurements",
      layout: {
        "text-ignore-placement": true, // Need to be able to stack symbols at same location
        "text-anchor": "left",
        "text-offset": getLabelOffset(),
        "text-field": isShowSpotLabelsOn ? getPointLabel() : "",
        "icon-image": getIconImageExt(),
        "icon-rotate": getIconRotation(),
        "icon-rotation-alignment": "map",
        "icon-allow-overlap": true, // Need to be able to stack symbols at same location
        "icon-ignore-placement": true, // Need to be able to stack symbols at same location
        "icon-size": 0.15,
        "symbol-spacing": 1,
      },
    },
    // {
    //   id: "point-color-halo",
    //   type: "circle",
    //   source: "measurements",
    //   circleRadius: 17,
    //   circleColor: ["get", "circleColor", ["get", "symbology"]],
    // },
  ];

  return symbolLayers;
};

export { pointLayers };
