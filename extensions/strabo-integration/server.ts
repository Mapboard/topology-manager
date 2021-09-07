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
  app.get("/spots", async function (req, res) {
    const fn = require.resolve("./sql/get-spots.sql");
    const spots = await db.query(sql(fn));
    const features = spots.map((spot) => {
      const { data, id } = spot;
      return data;
    });
    return res.json({ features, type: "FeatureCollection" });
  });

  app.get("/measurements", async function (req, res) {
    const fn = require.resolve("./sql/get-spots.sql");
    const spots = await db.query(sql(fn));

    const features = [];
    // Unnest measurement data from spots data structure
    for (const spot of spots) {
      const { properties, ...spotData } = spot.data;
      const { orientation_data = [], ...coreProperties } = properties;
      for (const measurement of orientation_data) {
        const { associated_orientaton = [], ...orientation } = measurement;
        features.push({
          ...spotData,
          properties: {
            ...coreProperties,
            orientation,
            id: orientation.id,
            spot_id: coreProperties.id,
          },
        });

        for (const orientation of associated_orientaton) {
          features.push({
            ...spotData,
            properties: {
              ...coreProperties,
              orientation,
              id: orientation.id,
              spot_id: coreProperties.id,
            },
          });
        }
      }
    }

    return res.json({ features, type: "FeatureCollection" });
  });

  return app;
};

module.exports = { measurementsServer };
