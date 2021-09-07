function getMeasurements() {
  const { data: polygonTypes } = await get(
    sourceURL + "/feature-server/polygon/types"
  );
}
