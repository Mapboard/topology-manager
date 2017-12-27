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
       .replace /\/\*[\s\S]*?\*\/|--.*?$/gm, ''
  arr = /^[\s\n]*([A-Z\s]+[a-zA-Z_."]*)/g
    .exec(s)
  if arr? and arr[1]?
    s = arr[1]
  console.log s.replace(/"/g,'').gray

runQuery = (q)->
  try
    queryInfo(q)
    await db.query q
  catch err
    ste = err.toString()
    if ste.endsWith "already exists"
      console.error ste.dim.red
    else
      console.error ste.red

proc = (fn)->
  ## Execute a (likely multi-transaction) stored procedure
  try
    _ = sql(fn)
    procedures = TSParser.parse _,'pg',';'
    console.log fn.green
    db.tx (ctx)->
      for q in procedures
        await runQuery(q)
      console.log ""
  catch err
    console.error "#{err.stack}".red

module.exports = {db,sql,proc}
