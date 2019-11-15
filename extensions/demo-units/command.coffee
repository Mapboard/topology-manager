{db, proc, sql} = require '../../src/util.coffee'
{join, resolve} = require 'path'
http = require 'http'

sqlFile = (id)->
  resolve join(__dirname,'procedures',"#{id}.sql")

csvFile = (id)->
  resolve(join(__dirname,'defs',"#{id}.csv"))

importCSV = (opts)->
  q = sql sqlFile('02-import-from-csv')
  db.query(q,opts)

command = 'create-demo-units'
describe = 'Create demo units'

handler = ->
  await proc(sqlFile('01-create-temp-tables'))
  await importCSV({
      tablename: 'tmp_linework_type',
      csvfile: csvFile('linework-types')
    })
  await importCSV({
      tablename: 'tmp_polygon_type',
      csvfile: csvFile('polygon-types')
    })
  await proc(sqlFile('03-add-to-map'))

module.exports = {command, describe, handler}
