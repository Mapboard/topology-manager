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
  const tags = data.projectDb.project.tags;

  await proc(sqlFile("create-tables"), {});

  for (const [id, data] of Object.entries(spots)) {
    await db.query(sql(sqlFile("insert-spot")), { id, data });
  }

  for (const data of tags) {
    const { id, spots = [] } = data;
    console.log(data.name);
    await db.query(sql(sqlFile("insert-tag")), { id, data });
    for (const spot_id of spots) {
      console.log(spot_id);
      await db.query(sql(sqlFile("insert-tag-relationships")), {
        tag_id: id,
        spot_id,
      });
    }
  }
};

module.exports = {
  command: "import-strabo [file]",
  describe: "Import a Strabo project backup",
  handler,
};
