/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const { db, sql } = require("../util");
const colors = require("colors");

const getContactsWithErrors = sql("procedures/get-contacts-with-errors");

async function handler(argv) {
  const rows = await db.query(getContactsWithErrors);
  for (const { id, topology_error } of rows) {
    console.log(`${id}`.gray + ` ${topology_error}`.red);
  }
  process.exit(0);
}

module.exports = {
  command: "errors",
  describe: "Show topology errors",
  handler,
};
