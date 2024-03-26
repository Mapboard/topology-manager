/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS202: Simplify dynamic range loops
 * DS205: Consider reworking code to avoid use of IIFEs
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const SphericalMercator = require("@mapbox/sphericalmercator");
const Promise = require("bluebird");
const { promisify } = require("util");
const { SingleBar } = require("cli-progress");
const MBTiles = require("@mapbox/mbtiles");
const zlib = require("zlib");

const { vectorTileInterface } = require("./tile-factory");
const cfg = require("../../../src/config");

const command = "export-mbtiles [--layer LYR] [--zoom-range MIN,MAX] FILE";
const describe = "Export a Mapbox Studio compatible vector tileset";

const merc = new SphericalMercator({ size: 256 });

const tileCoords = function* (zoomLevels, bounds) {
  return yield* function* () {
    const result = [];
    for (var z of Array.from(zoomLevels)) {
      var { minX, maxX, minY, maxY } = merc.xyz(bounds, z);
      result.push(
        yield* function* () {
          const result1 = [];
          for (
            var x = minX, end = maxX, asc = minX <= end;
            asc ? x <= end : x >= end;
            asc ? x++ : x--
          ) {
            result1.push(
              yield* function* () {
                const result2 = [];
                for (
                  let y = minY, end1 = maxY, asc1 = minY <= end1;
                  asc1 ? y <= end1 : y >= end1;
                  asc1 ? y++ : y--
                ) {
                  result2.push(yield { z, x, y });
                }
                return result2;
              }.call(this)
            );
          }
          return result1;
        }.call(this)
      );
    }
    return result;
  }.call(this);
};

const handler = async function (argv) {
  const filename = argv.FILE;
  const layer = argv.LYR || "map-data";

  let { bounds, zoomRange } = cfg["live-tiles"];
  if (argv.zoomRange != null) {
    zoomRange = argv.zoomRange.split(",").map((d) => parseInt(d.trim()));
  }

  const zoomLevels = __range__(zoomRange[0], zoomRange[1], true);

  let total = 0;
  for (let z of Array.from(zoomLevels)) {
    const { minX, maxX, minY, maxY } = merc.xyz(bounds, z);
    const n = (maxX - minX) * (maxY - minY);
    total += n;
    console.log(`zoom ${z}: ${n} tiles`);
  }
  console.log(`  total: ${total} tiles`);

  const [minzoom, maxzoom] = zoomRange;

  const data = {
    name: "geologic-map",
    description: "Geologic map data",
    format,
    version: 2,
    minzoom,
    maxzoom,
    bounds,
    type: "overlay",
    json: JSON.stringify({
      vector_layers: [
        { id: layer, description: "", minzoom, maxzoom, fields: {} },
      ],
    }),
  };

  const mbtiles = await new (promisify(MBTiles))(filename + "?mode=rwc");
  const mbtOp = (name, ...rest) =>
    promisify(mbtiles[name].bind(mbtiles))(...rest);

  // Actually write everything
  await mbtOp("startWriting");
  await mbtOp("putInfo", data);

  const progressBar = new SingleBar();
  progressBar.start(total);

  var { getTile, format } = await vectorTileInterface(layer, { silent: true });
  const coords = tileCoords(zoomLevels, bounds);
  const fn = async function ({ z, x, y }) {
    const tile = await getTile({ z, x, y });
    // Tiles must be gzipped
    const ztile = await promisify(zlib.gzip)(tile);
    await mbtOp("putTile", z, x, y, ztile);
    return progressBar.increment();
  };

  // Insert actual tiles
  await Promise.mapSeries(coords, fn, { concurrency: 8 });

  await mbtOp("stopWriting");
  return progressBar.stop();
};

module.exports = { command, describe, handler };

function __range__(left, right, inclusive) {
  let range = [];
  let ascending = left < right;
  let end = !inclusive ? right : ascending ? right + 1 : right - 1;
  for (let i = left; ascending ? i < end : i > end; ascending ? i++ : i--) {
    range.push(i);
  }
  return range;
}
