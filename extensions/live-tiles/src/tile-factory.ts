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

module.exports = { vectorTileInterface };
