/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const express = require("express");
const responseTime = require("response-time");
const { db, sql } = require("../../src/util");

const measurementsServer = function () {
  const app = express().disable("x-powered-by");
  app.use(responseTime());
  app.get("/", async function (req, res) {
    const fn = require.resolve("./sql/get-spots.sql");
    const spots = await db.one(sql(fn));
    return res.json(spots);
  });

  return app;
};

module.exports = { measurementsServer };
