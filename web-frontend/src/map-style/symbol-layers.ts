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
};

function createLineSymbolLayers() {
  let symbolLayers = [];
  for (const lyr of lineSymbols) {
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
        "icon-size": {
          stops: [
            [5, 0.2],
            [16, 1],
          ],
        },
      },
      paint: {
        "icon-color": ["get", "color"],
      },
      filter: ["==", ["get", "type"], lyr],
    };
    symbolLayers.push(val);
  }
  return symbolLayers;
}

export { lineSymbols, createLineSymbolLayers };
