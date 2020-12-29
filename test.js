require("coffeescript/register");
const test = require("ava");
const { db, sql } = require("./src/util");

test("basic insert", async (t) => {
  const s1 = sql("test-fixtures/basic-insert");
  const res = await db.query(s1);
  t.is(res.length, 1);
  console.log(res[0]);
  t.is(res[0]["type"], "bedrock");
  t.pass();
});

test("insert using stored procedure", async (t) => {
  const s1 = sql("./packages/mapboard-server/sql/new-line");
  const res = await db.query(s1, {
    schema: "map_digitizer",
    snap_width: 0,
    snap_types: [],
    type: "bedrock",
    pixel_width: null,
    map_width: null,
    certainty: null,
    zoom_level: null,
    geometry: "LINESTRING(0 0,1 0)",
  });
  t.is(res.length, 1);
  console.log(res[0]);
  t.is(res[0]["type"], "bedrock");
  t.pass();
});
