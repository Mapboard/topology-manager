require("coffeescript/register");
require("ts-node").register({
  transpileOnly: true,
});
const { serial: test } = require("ava");
const { db, sql } = require("./src/util");
const { createCoreTables } = require("./src/commands/create-tables");
const { handler: createDemoUnits } = require("./extensions/demo-units/command");
const { updateAll } = require("./src/commands/update");

test.before(async (d) => {
  await createCoreTables();
  await createDemoUnits();

  // These are needed because it the mapboard-server tests get run first
  // by default.
  await db.query("TRUNCATE TABLE map_digitizer.linework CASCADE");
  await db.query("TRUNCATE TABLE map_digitizer.polygon CASCADE");
});

test("basic insert", async (t) => {
  const s1 = sql("test-fixtures/basic-insert");
  const res = await db.query(s1);
  t.is(res.length, 1);
  t.is(res[0]["type"], "bedrock");
  t.pass();
});

test("insert using stored procedure", async (t) => {
  const s1 = sql("./packages/mapboard-server/sql/new-line");
  const res = await db.one(s1, {
    schema: "map_digitizer",
    snap_width: 0,
    snap_types: [],
    type: "bedrock",
    pixel_width: null,
    map_width: null,
    certainty: null,
    zoom_level: null,
    geometry: "LINESTRING(16.1 -24.3,16.2 -24.4)",
  });
  t.is(res["type"], "bedrock");
  t.pass();
});

const insertFeature = sql("./test-fixtures/insert-feature");

test("insert in native projection", async (t) => {
  const res = await db.one(insertFeature, {
    type: "bedrock",
    table: "linework",
    geometry: "LINESTRING(0 0, 5 0)",
  });
  t.is(res["type"], "bedrock");
  t.pass();
});

var lineChangeID;

test("insert a connecting line, creating a triangle", async (t) => {
  const res = await db.one(insertFeature, {
    type: "bedrock",
    table: "linework",
    geometry: "LINESTRING(5 0, 3 4, 0 0)",
  });
  t.is(res["type"], "bedrock");
  lineChangeID = res.id;
  t.pass();
});

test("insert a polygon identifying unit within the triangle", async (t) => {
  const type = "upper-omkyk";
  const res = await db.one(insertFeature, {
    type,
    table: "polygon",
    geometry: "POLYGON((2 0.5, 3 0.5, 3 1, 2 0.5))",
  });
  t.is(res["type"], type);
  t.pass();
});

test("solve topology and check that we have a map face", async (t) => {
  await updateAll();
  const res = await db.query("SELECT * FROM map_topology.map_face");
  t.is(res["length"], 1);
});

test("change a line type", async (t) => {
  const line_id = lineChangeID;
  const res = await db.query(
    "UPDATE map_digitizer.linework SET type = 'anticline-hinge' WHERE id = ${line_id} RETURNING id",
    { line_id }
  );
  t.is(res.length, 1);

  await updateAll();
  const res1 = await db.query("SELECT * FROM map_topology.map_face");
  t.is(res1.length, 0);
});

test("tables have been created in correct schema", async (t) => {
  const q = sql("test-fixtures/table-exists");
  const res = await db.one(q, { schema: "map_digitizer", table: "linework" });
  t.is(res.exists, false);

  const res2 = await db.one(q, {
    schema: "map_digitizer_test",
    table: "linework",
  });
  t.is(res2.exists, true);
});
