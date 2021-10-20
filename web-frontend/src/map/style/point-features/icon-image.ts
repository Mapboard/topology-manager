/** Functions for getting the proper icon symbol for measurement features. */

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

export function getOrientationSymbolName(o: OrientationData) {
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

export function preprocessMeasurement(measurement: MeasurementData) {
  /**
   * Prepare a measurement for use on the map, by programmatically setting the
   * name of the appropriate orientation symbol.
   */

  measurement.properties.symbology ??= {};
  measurement.properties.symbol_name = getOrientationSymbolName(
    measurement.properties.orientation
  );

  return measurement;
}

export function getIconImage() {
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
}

export function getIconImageExt() {
  /** Extension to Strabo-provided getIconImage that modifies the style tree to use programmatic definition of icon image if provided. */
  return [
    "case",
    ["has", "symbol_name"],
    ["get", "symbol_name"],
    getIconImage(),
  ];
}
