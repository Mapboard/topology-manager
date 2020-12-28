const test = require("ava");

test("should pass", (t) => {
  t.pass();
});

test("should pass async", async (t) => {
  const bar = Promise.resolve("res");
  t.is(await bar, "res");
});
