PGPromise = require 'pg-promise'
{join, resolve} = require 'path'
colors = require 'colors'
Promise = require 'bluebird'
{TSParser} = require 'tsparser'
{readFileSync} = require 'fs'

{srid, topo_schema,
 data_schema, connection, tolerance} = require './config'

logFunc = (e)->
  console.log colors.grey(e.query)
  if e.params?
    console.log "    "+colors.cyan(e.params)
logFunc = null

pgp = PGPromise(promiseLib: Promise, query: logFunc)

{QueryFile} = pgp
{readFileSync} = require 'fs'

db = pgp(connection)

__base = resolve __dirname, '..'

queryIndex = {}

sql = (fn)->
  # Function to get sql queries from a file
  params = {topo_schema, data_schema, srid, tolerance}
  if not fn.endsWith('.sql')
    fn += '.sql'
  p = join __base, fn
  unless queryIndex[p]?
    # Using queryFile because it is best-documented
    # way to pre-format SQL. We could probably use
    # its internal interface
    _ = readFileSync p, 'utf8'
    _ = pgp.as.format(_, params, {partial: true})
    queryIndex[p] = _
    return queryIndex[p]

queryInfo = (queryText)->
  s = queryText
       .replace /\/\*[\s\S]*?\*\/|--.*?$/, ''
       .replace /\s*\n/, ''
       .replace /"/,''
  arr = /^\s*[A-Z\s]+[a-zA-Z_.]*/
    .exec(s)
  console.log arr[0].gray


proc = (fn)->
  ## Execute a (likely multi-transaction) stored procedure
  _ = sql(fn)
  procedures = TSParser.parse _,'pg',';'
  console.log fn.green
  db.tx (ctx)->
    for q in procedures
      queryInfo(q)
      try
        res = await db.query q
      catch err
        console.error err.toString().red
    console.log ""

module.exports = {db,sql,proc}
