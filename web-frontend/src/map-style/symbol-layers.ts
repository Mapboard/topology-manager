const lineSymbols = [
  "anticline-hinge",
  "left-lateral-fault",
  "normal-fault",
  "reverse-fault",
  "right-lateral-fault",
  "syncline-hinge",
  "thrust-fault",
];

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
        "icon-allow-overlap": true,
        "symbol-avoid-edges": false,
        "symbol-placement": "line",
        "symbol-spacing": 100,
      },
      filter: ["==", ["get", "type"], lyr],
    };
    symbolLayers.push(val);
  }
  return symbolLayers;
}

export { lineSymbols, createLineSymbolLayers };
