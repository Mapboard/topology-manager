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
  const { tiles = {}, port = 3006 } = serverCfg;
  const verbose = false;

  const app = appFactory({
    connection,
    tiles,
    schema: data_schema,
    topology: topo_schema,
    createFunctions: false,
    projectBounds,
  });
  app.use(cors());

  // This should be conditional
  const { liveTileServer } = require("../extensions/live-tiles/server");
  app.use("/live-tiles", liveTileServer(cfg));

  const server = createServer(app);
  startWatcher(verbose);

  server.listen(port, () => console.log(`Listening on port ${port}`));
};

module.exports = { command, describe, handler };
