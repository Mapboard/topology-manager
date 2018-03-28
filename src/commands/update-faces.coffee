ProgressBar = require 'progress'
{db,sql, proc} = require '../util'

count = "SELECT count(*)::integer nfaces FROM map_topology.__dirty_face"
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

  await proc "procedures/prepare-update-face"


  console.time "Updating faces"
  {nfaces} = await db.one count
  bar = new ProgressBar('Updating faces :bar :current/:total (:eta s)', { total: nfaces })

  while nfaces > 0
    await db.query "SELECT map_topology.update_map_face()"
    {nfaces: next} = await db.one count
    bar.tick nfaces-next
    nfaces = next
  console.timeEnd "Updating faces"

handler = (argv)->
  await updateFaces(argv)
  process.exit()

builder = (yargs)->
  yargs
    .option 'fill-holes', {default: false, description: 'Try to fill all holes'}
    .option 'reset', {default: false, description: 'Rebuild from scratch'}
  yargs

module.exports = {command, describe, handler, builder, updateFaces}

