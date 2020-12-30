require("coffeescript/register");
const test = require("ava");
const { db, sql } = require("./src/util");
const { createCoreTables } = require("./src/commands/create-tables");
const { handler: createDemoUnits } = require("./extensions/demo-units/command");
const { updateAll } = require("./src/commands/update");

test.before(async (d) => {
  await createCoreTables();
  await createDemoUnits();
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

test.serial("insert in native projection", async (t) => {
  const res = await db.one(insertFeature, {
    type: "bedrock",
    table: "linework",
    geometry: "LINESTRING(0 0, 5 0)",
  });
  t.is(res["type"], "bedrock");
  t.pass();
});

var lineChangeID;

test.serial("insert a connecting line, creating a triangle", async (t) => {
  const res = await db.one(insertFeature, {
    type: "bedrock",
    table: "linework",
    geometry: "LINESTRING(5 0, 3 4, 0 0)",
  });
  t.is(res["type"], "bedrock");
  lineID = res.id;
  t.pass();
});

test.serial(
  "insert a polygon identifying unit within the triangle",
  async (t) => {
    const type = "upper-omkyk";
    const res = await db.one(insertFeature, {
      type,
      table: "polygon",
      geometry: "POLYGON((2 0.5, 3 0.5, 3 1, 2 0.5))",
    });
    t.is(res["type"], type);
    t.pass();
  }
);

test.serial("solve topology and check that we have a map face", async (t) => {
  await updateAll();
  const res = await db.query("SELECT * FROM map_topology.map_face");
  t.is(res["length"], 1);
});

test.serial("change a line type", async (t) => {
  const line_id = lineChangeID;
  console.log(line_id);
  await db.query(
    "UPDATE map_digitizer.linework SET type = 'anticline-hinge' WHERE id = ${line_id}",
    { line_id }
  );
  await updateAll();
  const res = await db.query("SELECT * FROM map_topology.map_face");
  t.is(res["length"], 0);
});
