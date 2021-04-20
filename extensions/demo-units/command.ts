/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const { db, proc, sql, logQueryInfo } = require("../../src/util");
const { join, resolve } = require("path");
const http = require("http");
const Promise = require("bluebird");
const { createReadStream } = require("fs");
const { from: copyFrom } = require("pg-copy-streams");

const sqlFile = (id) => resolve(join(__dirname, "procedures", `${id}.sql`));

const csvFile = (id) => resolve(join(__dirname, "defs", `${id}.csv`));

const importCSV = async function (csvFile, tablename) {
  const conn = await db.connect();
  const { client } = conn;
  const fileStream = createReadStream(csvFile);
  return new Promise(function (resolve, reject) {
    const done = function (err) {
      conn.done();
      if (err) {
        return reject(err);
      } else {
        return resolve();
      }
    };
    const q = sql(sqlFile("02-import-from-csv")).replace(
      "${tablename~}",
      tablename
    );
    logQueryInfo(q);
    const stream = client.query(copyFrom(q));
    fileStream.on("error", done);
    stream.on("error", done);
    stream.on("finish", done);
    return fileStream.pipe(stream);
  });
};

const command = "create-demo-units";
const describe = "Create demo units";

const handler = async function () {
  console.log("Importing demo units");
  await proc(sqlFile("01-create-temp-tables"));
  await importCSV(csvFile("linework-types"), "tmp_linework_type");
  await importCSV(csvFile("polygon-types"), "tmp_polygon_type");
  return await proc(sqlFile("03-add-to-map"));
};

module.exports = { command, describe, handler };
