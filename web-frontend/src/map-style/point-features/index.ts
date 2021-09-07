function measurementsSource(sourceURL) {
  return {
    measurements: {
      type: "geojson",
      data: sourceURL + "/measurements",
    },
  };
}

function measurementsLayers() {
  return [
    {
      source: "measurements",
      id: "measurements",
      type: "circle",
      paint: {
        "circle-color": ["get", "circleColor", ["get", "symbology"]],
        "circle-stroke-color": "#dee4fb",
        "circle-stroke-width": 1,
        "circle-radius": 3,
      },
    },
  ];
}

export { measurementsSource, measurementsLayers };
