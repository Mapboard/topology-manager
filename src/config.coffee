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

newExtensions = []
for k,v of extensions
  prefix = 'file:'
  if v.startsWith prefix
    _ = v.slice prefix.length
    loc = resolve join cfgDir, _
  else
    loc = require.resolve v
  console.log loc
  cfg = require join(loc,'package.json')
  cfg.path = loc
  newExtensions.push cfg
extensions = newExtensions

basedir = resolve join __dirname, '..'

module.exports = {connection, data_schema,
                  topo_schema, tolerance, srid
                  basedir, server, extensions}
