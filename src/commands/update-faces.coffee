{db,sql, proc} = require '../util'

count = "SELECT count(*) nfaces FROM map_topology.__dirty_face"
command = 'update-faces [--reset] [--fill-holes]'
describe = 'Update map faces'

updateFaces = (opts={})->
  {reset, fillHoles} = opts
  reset ?= false
  fillHoles ?= false

  if reset
    await proc "procedures/reset-map-face"

  if fillHoles
    await proc "procedures/set-holes-as-dirty"

  await db.none "REFRESH MATERIALIZED VIEW map_topology.__face_relation"

  await proc "procedures/prepare-update-face"

  {nfaces} = await db.one count
  console.log "#{nfaces} remaining"
  while nfaces > 0
    await db.query "SELECT map_topology.update_map_face(false)"
    {nfaces} = await db.one count
    console.log "#{nfaces} remaining"

handler = (argv)->
  await updateFaces(argv)
  process.exit()

builder = (yargs)->
  yargs
    .option 'fill-holes', {default: false, description: 'Try to fill all holes'}
    .option 'reset', {default: false, description: 'Rebuild from scratch'}
  yargs

module.exports = {command, describe, handler, builder, updateFaces}

