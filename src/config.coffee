{GEOLOGIC_MAP_CONFIG} = process.env
{resolve,join, dirname, isAbsolute} = require 'path'
{existsSync} = require 'fs'
require 'tilelive-modules/loader'

if not GEOLOGIC_MAP_CONFIG?
  throw Error("Environment variable GEOLOGIC_MAP_CONFIG is not defined!")

{database, srid, topo_schema,
 data_schema, host, port,
 connection, tolerance, server,
 extensions, rest...} = require GEOLOGIC_MAP_CONFIG

host ?= 'localhost'
port ?= 5432
connection ?= { host, port, database } # Also needs user, password
data_schema ?= 'map_digitizer'
topo_schema ?= 'map_topology'
tolerance ?= 1
srid ?= 4326

cfgDir = dirname GEOLOGIC_MAP_CONFIG

basedir = resolve join __dirname, '..'
packageCfg = require '../package.json'

prefix = 'file:'

appRequire = (fn)->
  require join(basedir,fn)

cfgRequire = (fn)->
  require join(cfgDir,fn)

getFromFilePath = (cfgDir,v)->
  _ = v.slice prefix.length
  loc = resolve join cfgDir, _
  return loc

getLocation = (cfgDir, key, locString)->
  if isAbsolute(locString)
    return require.resolve locString
  if locString.startsWith prefix
    return getFromFilePath(cfgDir,locString)

  localVal = packageCfg.extensions[key]
  if localVal?
    return getFromFilePath(basedir,localVal)
  return require.resolve locString

configDir = cfgDir
config = {connection, data_schema, configDir
          topo_schema, tolerance, srid
          basedir, server, appRequire, cfgRequire,
          rest...}

# Make config accessible to extensions
# There is probably a better way to do this.
global.config = config
# Get configurations for each extension.
config.extensions = for k,v of extensions
  loc = getLocation(cfgDir, k, v)
  cfg = require join(loc,'package.json')
  if cfg.name != k
    throw "Extension name #{cfg.name} does not match configuration."
  cfg.path = loc
  cfg.commands ?= []
  cfg

module.exports = config
