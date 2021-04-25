const lineSymbols = [
  "anticline-hinge",
  "left-lateral-fault",
  "normal-fault",
  "reverse-fault",
  "right-lateral-fault",
  "syncline-hinge",
  "thrust-fault",
];

const spacing = {
  "anticline-hinge": 200,
  "syncline-hinge": 200,
  "thrust-fault": [
    "interpolate",
    ["exponential", 2],
    ["zoom"],
    0, // stop
    5, // size
    15,
    80,
    24,
    200,
  ],
};

function createLineSymbolLayers() {
  let symbolLayers = [];
  for (const lyr of lineSymbols) {
    let color: any = ["get", "color"];
    let offset: any = [0, 0];
    if (lyr == "thrust-fault") {
      color = "#000000";
      offset = [
        "interpolate",
        ["exponential", 2],
        ["zoom"],
        0,
        ["literal", [0, 0]],
        24,
        ["literal", [0, 0]],
      ];
    }

    const val = {
      id: `${lyr}-stroke`,
      source: "geology",
      "source-layer": "contact",
      type: "symbol",
      layout: {
        "icon-image": lyr,
        "icon-pitch-alignment": "map",
        "icon-allow-overlap": true,
        "symbol-avoid-edges": false,
        "symbol-placement": "line",
        "symbol-spacing": spacing[lyr] ?? 30,
        "icon-offset": offset,
        "icon-size": [
          "interpolate",
          ["exponential", 2],
          ["zoom"],
          0, // stop
          0.5,
          15,
          1.2, // size
          18,
          4,
          24,
          30,
        ],
      },
      paint: {
        "icon-color": color,
      },
      filter: ["==", ["get", "type"], lyr],
    };

    symbolLayers.push(val);
  }
  return symbolLayers;
}

export { lineSymbols, createLineSymbolLayers };
