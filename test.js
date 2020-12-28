require("coffeescript/register");
const test = require("ava");
const { db, sql } = require("./src/util");

test("should pass", (t) => {
  t.pass();
});

test("should pass async", async (t) => {
  const bar = Promise.resolve("res");
  t.is(await bar, "res");
});

test("insert data", async (t) => {
  const s1 = sql("test-fixtures/basic-insert");
  const res = await db.query(s1);
  t.is(res.length, 1);
  console.log(res[0]);
  t.is(res[0]["type"], "bedrock");
  t.pass();
});
