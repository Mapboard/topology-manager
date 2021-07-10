import { db, proc, sql, logQueryInfo, prepare } from "../../src/util";
import { join, resolve } from "path";
import Promise from "bluebird";
import { createReadStream } from "fs";
import { from as copyFrom } from "pg-copy-streams";
import { readFileSync } from "fs";

const sqlFile = (id) => resolve(join(__dirname, "sql", `${id}.sql`));

const handler = async function ({ file }) {
  console.log(`Importing backup from ${file}`);
  let projectDb = file;
  if (!projectDb.endsWith("data.json")) projectDb = join(file, "data.json");
  const data = JSON.parse(readFileSync(projectDb));
  const spots = data.spotsDb;
  console.log(Object.keys(spots).length);

  await proc(sqlFile("create-tables"), {});

  for (const [id, data] of Object.entries(spots)) {
    console.log(id);
    await db.query(sql(sqlFile("insert-spot")), { id, data });
  }
};

module.exports = {
  command: "import-strabo [file]",
  describe: "Import a Strabo project backup",
  handler,
};
