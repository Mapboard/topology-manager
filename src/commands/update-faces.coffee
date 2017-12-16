{argv} = require 'yargs'
{db,sql, proc} = require '../util'

count = "SELECT count(*) nfaces FROM map_topology.__dirty_face"
command = 'update-faces [--reset]'
describe = 'Update map faces'
handler = (argv)->
  if argv.reset?
    await proc "procedures/reset-map-face"

  await db.none "REFRESH MATERIALIZED VIEW map_topology.__face_relation"

  {nfaces} = await db.one count
  console.log "#{nfaces} remaining"
  while nfaces > 0
    await db.query "SELECT map_topology.update_map_face(false)"
    {nfaces} = await db.one count
    console.log "#{nfaces} remaining"

  process.exit()

module.exports = {command, describe, handler}

