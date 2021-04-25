/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const express = require("express");
const responseTime = require("response-time");
const cors = require("cors");
const morgan = require("morgan");
const { vectorTileInterface } = require("./src/tile-factory");
const { db, sql } = require("../../src/util");
const { createStyle } = require("./src/map-style");

const tileLayerServer = function ({ getTile, content_type, format, layer_id }) {
  // Small replacement for tessera

  const prefix = `/${layer_id}`;

  const app = express().disable("x-powered-by");
  app.use(prefix, responseTime());

  app.get(`/:z/:x/:y.${format}`, async function (req, res, next) {
    const z = req.params.z | 0;
    const x = req.params.x | 0;
    const y = req.params.y | 0;

    try {
      // Ignore headers that are also set by getTile
      const tile = await getTile({ z, x, y, layer_id });
      if (tile == null) {
        return res.status(404).send("Not found");
      }
      res.set({ "Content-Type": content_type });
      return res.status(200).send(tile);
    } catch (err) {
      return next(err);
    }
  });

  return app;
};

const liveTileServer = function (cfg) {
  const app = express().disable("x-powered-by");
  app.use(cors());

  if (process.env.NODE_ENV !== "production") {
    app.use(morgan("dev"));
  }

  app.get("/", (req, res) => res.send("Live tiles"));

  vectorTileInterface("map-data").then(function (cfg) {
    const server = tileLayerServer(cfg);
    return app.use("/map-data", server);
  });

  app.get("/style.json", async function (req, res) {
    const fn = require.resolve(
      "../server/map-digitizer-server/sql/get-feature-types.sql"
    );
    const polygonTypes = await db.query(sql(fn), {
      schema: "map_digitizer",
      table: "polygon_type",
    });
    return res.json(createStyle(polygonTypes, "http://Daven-Quinn.local:3006"));
  });

  return app;
};

module.exports = { liveTileServer };
