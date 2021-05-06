const { db, prepare } = require("../../../src/util");

const command = "clear-tile-cache";
const describe = "Clear cached vector tiles";

const handler = async function (argv) {
  await db.query(prepare("TRUNCATE TABLE tiles.tile"));
};

module.exports = { command, describe, handler };
