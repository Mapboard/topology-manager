import { db, proc, sql, logQueryInfo, prepare } from "../../src/util";
import { join, resolve } from "path";
import Promise from "bluebird";
import { createReadStream } from "fs";
import { from as copyFrom } from "pg-copy-streams";

const sqlFile = (id) => resolve(join(__dirname, "procedures", `${id}.sql`));

const handler = async function ({ file }) {
  console.log(`Importing backup from ${file}`);
};

module.exports = {
  command: "import-strabo [file]",
  describe: "Import a Strabo project backup",
  handler,
};
