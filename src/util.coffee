PGPromise = require 'pg-promise'
{join, resolve, isAbsolute} = require 'path'
colors = require 'colors'
Promise = require 'bluebird'
{TSParser} = require 'tsparser'
{readFileSync} = require 'fs'

{srid, topo_schema,
 data_schema, connection, tolerance} = require './config'

logFunc = (e)->
  return unless global.verbose
  #console.log global.verbose
  #return unless global.verbose
  console.log colors.grey(e.query)
  if e.params?
    console.log "    "+colors.cyan(e.params)

logNoticesFunction = (client, dc, isFresh) ->
  return unless isFresh
  return unless global.verbose
  client.on 'notice', (msg)->
    msg = String(msg).slice(8)
    console.log("NOTICE ".blue+msg)

pgp = PGPromise(promiseLib: Promise, query: logFunc, connect: logNoticesFunction)

{QueryFile} = pgp
{readFileSync} = require 'fs'

db = pgp(connection)

__base = resolve __dirname, '..'

queryIndex = {}

sql = (fn)->
  # Function to get sql queries from a file
  params = {topo_schema, data_schema, srid, tolerance}
  if isAbsolute(fn)
    p = fn
  else
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
  return s.replace(/"/g,'')

runQuery = (q, opts={})->
  opts.indent ?= ''
  try
    qi = queryInfo(q)
    console.log opts.indent+qi.gray
    await db.query q
  catch err
    ste = err.toString()
    if ste.endsWith "already exists"
      console.error opts.indent+ste.dim.red
    else
      console.error opts.indent+ste.red

proc = (fn, opts={})->
  ## Execute a (likely multi-transaction) stored procedure
  # Trim leading path for display if asked for
  {indent, trimPath} = opts
  indent ?= ''

  if trimPath?
    fnd = fn.replace(opts.trimPath,'')
    if fnd.indexOf('/') == 0
      fnd = fnd.substr(1)
  fnd ?= fn

  try
    _ = sql(fn)
    procedures = TSParser.parse _,'pg',';'
    console.log indent+fnd.green
    db.tx (ctx)->
      for q in procedures
        await runQuery(q, {indent})
      console.log ""
  catch err
    console.error indent+"#{err.stack}".red

module.exports = {db,sql,proc,__base}
