import { db, proc, sql, logQueryInfo, prepare } from "../../src/util";
import { join, resolve } from "path";
import Promise from "bluebird";
import { createReadStream } from "fs";
import { from as copyFrom } from "pg-copy-streams";

const sqlFile = (id) => resolve(join(__dirname, "procedures", `${id}.sql`));

const csvFile = (id) => resolve(join(__dirname, "defs", `${id}.csv`));

const importCSV = async function (csvFile, tablename) {
  console.log(tablename);
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
    const q = prepare(sql(sqlFile("02-import-from-csv")), { tablename });
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

export default { command, describe, handler };
