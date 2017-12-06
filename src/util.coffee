_ = require 'pg-promise'
query = null#(e)->console.log e.query
pgp = _ {query}
{join, resolve} = require 'path'
colors = require 'colors'

{database, srid, topo_schema,
 data_schema, host, port, connection, tolerance} = require '../config.json'

{QueryFile} = pgp
{readFileSync} = require 'fs'

host ?= 'localhost'
port ?= 5432
connection ?= { host, port, database, user, password}
tolerance ?= 1

db = pgp(connection)

__base = resolve __dirname, '..'

sql = (fn)->
  params = {topo_schema, data_schema, srid, tolerance}
  if not fn.endsWith('.sql')
    fn += '.sql'
  p = join __base, fn
  procedure = QueryFile p, {params}
  try
    res = await db.multi procedure
  catch err
    console.error fn
    console.error err.toString().red

module.exports = {db,sql}
