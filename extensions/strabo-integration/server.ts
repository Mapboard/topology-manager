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
    const spots = await db.query(sql(fn));
    const features = spots.map((spot) => {
      const { data, id } = spot;
      return data;
    });
    return res.json({ features, type: "FeatureCollection" });
  });

  return app;
};

module.exports = { measurementsServer };
