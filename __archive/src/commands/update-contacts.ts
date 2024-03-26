/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const ProgressBar = require("progress");
const { db, sql } = require("../util");
const colors = require("colors");
const Promise = require("bluebird");

const command = "update-contacts [--fix-failed]";
const describe = "Update topology for contacts";

const count = sql("procedures/count-contact");
const proc = sql("procedures/update-contact");
const resetErrors = sql("procedures/reset-linework-errors");
const getContacts = sql("procedures/get-contacts-to-update");
const postUpdateContacts = sql("procedures/post-update-contacts");

const updateContacts = async function (opts = {}) {
  let { fixFailed } = opts;
  if (fixFailed == null) {
    fixFailed = false;
  }

  if (fixFailed) {
    await db.query(resetErrors);
  }

  const { nlines } = await db.one(count);
  if (nlines === 0) {
    console.log("No contacts to update");
  }

  const rows = await db.query(getContacts);
  let remaining = rows.length;
  const __ = "Updating lines :bar :current/:total (:elapsed/:eta s)";
  const bar = new ProgressBar(__, { total: remaining });
  while (remaining > 0) {
    var err, result;
    const n = 10;
    try {
      var id;
      result = await db.query(proc, { n });
      for ({ id, err } of Array.from(result)) {
        if (err != null) {
          bar.interrupt(`${id}`.gray + ` ${err}`.red.dim);
        }
      }
    } catch (error) {
      err = error;
      console.error(err);
      bar.interrupt(`${err}`.red.dim);
    }
    bar.tick(result != null ? result.length : undefined);
    remaining -= (result != null ? result.length : undefined) || 0;
  }

  // Post-update (in an ideal world we would not have to do this)
  //console.log "Linking lines to topology edges".gray
  return await db.query(postUpdateContacts);
};

const handler = async function (argv) {
  await updateContacts(argv);
  return process.exit();
};

module.exports = { command, describe, handler, updateContacts };
