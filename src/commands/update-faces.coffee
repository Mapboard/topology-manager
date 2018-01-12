{db,sql, proc} = require '../util'

count = "SELECT count(*) nfaces FROM map_topology.__dirty_face"
command = 'update-faces [--reset]'
describe = 'Update map faces'

updateFaces = (reset=false)->
  if reset
    await proc "procedures/reset-map-face"

  await db.none "REFRESH MATERIALIZED VIEW map_topology.__face_relation"

  await proc "procedures/prepare-update-face"

  {nfaces} = await db.one count
  console.log "#{nfaces} remaining"
  while nfaces > 0
    await db.query "SELECT map_topology.update_map_face(false)"
    {nfaces} = await db.one count
    console.log "#{nfaces} remaining"

handler = (argv)->
  {reset} = argv
  await updateFaces(reset)
  process.exit()

module.exports = {command, describe, handler, updateFaces}

