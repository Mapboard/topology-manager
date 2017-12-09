{GEOLOGIC_MAP_CONFIG} = process.env
{resolve,join} = require 'path'

{database, srid, topo_schema,
 data_schema, host, port,
 connection, tolerance} = require GEOLOGIC_MAP_CONFIG

host ?= 'localhost'
port ?= 5432
connection ?= { host, port, database} # Also needs user, password
data_schema ?= 'map_digitizer'
topo_schema ?= 'map_topology'
tolerance ?= 1
srid ?= 4326

basedir = resolve join __dirname, '..'

module.exports = {connection, data_schema,
                  topo_schema, tolerance, srid
                  basedir}
