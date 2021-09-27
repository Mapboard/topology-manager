/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS205: Consider reworking code to avoid use of IIFEs
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
let v, loc;
const { GEOLOGIC_MAP_CONFIG } = process.env;
const { resolve, join, dirname, isAbsolute } = require("path");
const { existsSync } = require("fs");

if (GEOLOGIC_MAP_CONFIG == null) {
  console.log("Environment variable GEOLOGIC_MAP_CONFIG is not defined!");
  console.log(
    "It must be set to the absolute path to a JSON file to continue."
  );
  process.exit(1);
}

process.env.GEOLOGIC_MAP_SOURCE_DIR = __dirname;

let {
  database,
  srid,
  topo_schema,
  data_schema,
  host,
  port,
  connection,
  tolerance,
  server,
  extensions,
  commandName = "geologic-map",
  ...rest
} = require(GEOLOGIC_MAP_CONFIG) ?? {};

if (host == null) {
  host = "localhost";
}
if (port == null) {
  port = 5432;
}
if (connection == null) {
  // Handle old format of connection information
  connection = { host, port, database };
} // Also needs user, password
if (process.env.GEOLOGIC_MAP_DATABASE_CONNECTION != null) {
  // Override connection information from environment variable
  connection = process.env.GEOLOGIC_MAP_DATABASE_CONNECTION;
}

if (data_schema == null) {
  data_schema = "map_digitizer";
}
if (topo_schema == null) {
  topo_schema = "map_topology";
}
if (tolerance == null) {
  tolerance = 1;
}
if (srid == null) {
  srid = 4326;
}

const cfgDir = dirname(GEOLOGIC_MAP_CONFIG);

const basedir = resolve(join(__dirname, ".."));
const packageCfg = require("../package.json");

if (process.env.GEOLOGIC_MAP_SERVER_PORT != null) {
  server.port = parseInt(process.env.GEOLOGIC_MAP_SERVER_PORT);
}

const prefix = "file:";

const appRequire = (fn) => require(join(basedir, fn));

const cfgRequire = (fn) => require(join(cfgDir, fn));

const getFromFilePath = function (cfgDir, v) {
  const _ = v.slice(prefix.length);
  loc = resolve(join(cfgDir, _));
  return loc;
};

const getLocation = function (cfgDir, key, locString) {
  if (isAbsolute(locString)) {
    return require.resolve(locString);
  }
  if (locString.startsWith(prefix)) {
    return getFromFilePath(cfgDir, locString);
  }

  const localVal = packageCfg.extensions[key];
  if (localVal != null) {
    return getFromFilePath(basedir, localVal);
  }
  return require.resolve(locString);
};

const configDir = cfgDir;
const config = {
  connection,
  data_schema,
  configDir,
  topo_schema,
  tolerance,
  srid,
  basedir,
  server,
  appRequire,
  cfgRequire,
  commandName,
  ...rest,
};

// Make config accessible to extensions
// There is probably a better way to do this.
global.config = config;
// Get configurations for each extension.
config.extensions = (() => {
  const result = [];
  for (let k in extensions) {
    v = extensions[k];
    loc = getLocation(cfgDir, k, v);
    const cfg = require(join(loc, "package.json"));
    if (cfg.name !== k) {
      throw `Extension name ${cfg.name} does not match configuration.`;
    }
    cfg.path = loc;
    if (cfg.commands == null) {
      cfg.commands = [];
    }
    result.push(cfg);
  }
  return result;
})();

module.exports = config;
