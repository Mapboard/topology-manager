/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS202: Simplify dynamic range loops
 * DS205: Consider reworking code to avoid use of IIFEs
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */

const { db, prepare } = require("../../../src/util");

const command = "clear-tile-cache";
const describe = "Clear cached vector tiles";

const handler = async function (argv) {
  await db.query(prepare("TRUNCATE TABLE tiles.tile"));
};

module.exports = { command, describe, handler };
