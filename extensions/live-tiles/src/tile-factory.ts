/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const loader = require("tilelive-modules/loader");
const { memoize } = require("underscore");
const Promise = require("bluebird");
const cache = require("tilelive-cache");
const tilelive = cache(require("@mapbox/tilelive"));
const { db, sql: __sql } = require("../../../src/util");

const sql = (id) => __sql(require.resolve(`../procedures/${id}.sql`));

const interfaceFactory = async function (name, opts, buildTile) {
  let { silent } = opts;
  if (silent == null) {
    silent = false;
  }
  const log = silent ? function () {} : console.log;
  const { id: layer_id, content_type, format } = await db.one(
    sql("get-tile-metadata"),
    { name }
  );
  const q = sql("get-tile");
  const q2 = sql("set-tile");
  const getTile = async function (tileArgs) {
    const { z, x, y } = tileArgs;
    let { tile } = (await db.oneOrNone(q, { ...tileArgs, layer_id })) || {};
    if (tile == null) {
      log(`Creating tile (${z},${x},${y}) for layer ${name}`);
      tile = await buildTile(tileArgs);
      db.none(q2, { z, x, y, tile, layer_id });
    }
    return tile;
  };
  return { getTile, content_type, format, layer_id };
};

const tileliveInterface = async function (name, uri) {
  uri += "?tileSize=512&scale=2";
  loader(tilelive, {});
  const loadURI = Promise.promisify(tilelive.load);
  const source = await loadURI(uri);
  const opts = { context: source };
  const getTile = Promise.promisify(source.getTile, opts);

  return interfaceFactory(name, async function (tileArgs) {
    const { z, x, y } = tileArgs;
    return await getTile(z, x, y);
  });
};

const vectorTileInterface = function (layer, opts) {
  if (opts == null) {
    opts = {};
  }
  const q = sql("get-vector-tile");
  return interfaceFactory(layer, opts, async function (tileArgs) {
    const { tile } = await db.one(q, tileArgs);
    return tile;
  });
};

module.exports = { vectorTileInterface, tileliveInterface };
