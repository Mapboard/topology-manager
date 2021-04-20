/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const {db} = require('../../src/util.coffee');
const cfg = require('../../src/config');
const {startWatcher} = require('../../src/commands/update');
const {appFactory, createServer} = require('mapboard-server');
const express = require('express');
const {join} = require('path');
const http = require('http');

const command = 'serve';
const describe = 'Create a feature server';

let {server, data_schema, connection} = cfg;

const handler = function() {
  let verbose;
  if (server == null) { server = {}; }
  let {tiles, port} = server;
  if (tiles == null) { tiles = {}; }
  if (port == null) { port = 3006; }
  const app = appFactory({connection, tiles, schema: data_schema, createFunctions: false});

  // This should be conditional
  const {liveTileServer} = require('../live-tiles/server');
  app.use('/live-tiles', liveTileServer(cfg));

  server = createServer(app);
  startWatcher(verbose=false);

  return server.listen(port, () => console.log(`Listening on port ${port}`));
};

module.exports = {command, describe, handler};
