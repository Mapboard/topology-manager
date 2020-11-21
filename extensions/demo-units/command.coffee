{db, proc, sql, logQueryInfo} = require '../../src/util.coffee'
{join, resolve} = require 'path'
http = require 'http'
Promise = require 'bluebird'
{createReadStream} = require 'fs'
{from: copyFrom} = require 'pg-copy-streams'

sqlFile = (id)->
  resolve join(__dirname,'procedures',"#{id}.sql")

csvFile = (id)->
  resolve(join(__dirname,'defs',"#{id}.csv"))

importCSV = (csvFile, tablename)->
  conn = await db.connect()
  {client} = conn
  fileStream = createReadStream(csvFile)
  return new Promise (resolve, reject)->
    done = (err)->
      conn.done()
      if err
        reject(err)
      else
        resolve()
    q = sql(sqlFile('02-import-from-csv')).replace("${tablename~}", tablename)
    logQueryInfo(q)
    stream = client.query(copyFrom(q))
    fileStream.on('error', done)
    stream.on('error', done)
    stream.on('finish', done)
    fileStream.pipe(stream)

command = 'create-demo-units'
describe = 'Create demo units'

handler = ->
  console.log('Importing demo units')
  await proc(sqlFile('01-create-temp-tables'))
  await importCSV(csvFile('linework-types'), 'tmp_linework_type')
  await importCSV(csvFile('polygon-types'), 'tmp_polygon_type')
  await proc(sqlFile('03-add-to-map'))

module.exports = {command, describe, handler}
