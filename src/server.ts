const { db } = require("./util");
const cfg = require("./config");
const { startWatcher } = require("./commands/update");
const { appFactory, createServer } = require("mapboard-server");
const express = require("express");
const { join } = require("path");
const http = require("http");
const cors = require("cors");

const command = "serve";
const describe = "Create a feature server";

const {
  server: serverCfg = {},
  projectBounds,
  data_schema,
  topo_schema,
  connection,
} = cfg;

const handler = function () {
  console.log(cfg);
  const { tiles = {}, port = 3006 } = serverCfg;
  const verbose = false;

  const app = express();

  const featureServer = appFactory({
    connection,
    tiles,
    schema: data_schema,
    topology: topo_schema,
    createFunctions: false,
    projectBounds,
  });

  app.use("/feature-server", createServer(featureServer));
  app.use(cors());

  // This should be conditional
  const { liveTileServer } = require("../extensions/live-tiles/server");
  app.use("/live-tiles", liveTileServer(cfg));

  startWatcher(verbose);

  app.listen(port, () => console.log(`Listening on port ${port}`));
};

module.exports = { command, describe, handler };
