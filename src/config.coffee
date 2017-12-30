{GEOLOGIC_MAP_CONFIG} = process.env
{resolve,join, dirname} = require 'path'
{existsSync} = require 'fs'

{database, srid, topo_schema,
 data_schema, host, port,
 connection, tolerance, server,
 extensions} = require GEOLOGIC_MAP_CONFIG

host ?= 'localhost'
port ?= 5432
connection ?= { host, port, database} # Also needs user, password
data_schema ?= 'map_digitizer'
topo_schema ?= 'map_topology'
tolerance ?= 1
srid ?= 4326

cfgDir = dirname GEOLOGIC_MAP_CONFIG

basedir = resolve join __dirname, '..'
packageCfg = require '../package.json'

prefix = 'file:'

getFromFilePath = (cfgDir,v)->
  _ = v.slice prefix.length
  loc = resolve join cfgDir, _
  return loc

getLocation = (cfgDir, key, locString)->
  if locString.startsWith prefix
    return getFromFilePath(cfgDir,locString)

  localVal = packageCfg.extensions[key]
  console.log key, localVal
  if localVal?
    return getFromFilePath(basedir,localVal)
  return require.resolve locString

newExtensions = []
for k,v of extensions
  loc = getLocation(cfgDir, k, v)
  cfg = require join(loc,'package.json')
  if cfg.name != k
    throw "Extension name #{cfg.name} does not match configuration."
  cfg.path = loc
  newExtensions.push cfg
extensions = newExtensions

module.exports = {connection, data_schema,
                  topo_schema, tolerance, srid
                  basedir, server, extensions}
