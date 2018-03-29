#!/usr/bin/env coffee
{proc, db, sql} = require '../util'
colors = require 'colors'

command = 'clean-topology'
describe = 'Clean topology'

deleteEdges = ->
  rem_edge = sql('procedures/clean-topology-rem-edge')
  await proc('procedures/clean-topology-01')
  await db.task (t)->
    console.log "Deleting edges".green.bold
    edges = await db.query sql('procedures/get-edges-to-delete')
    for {edge_id} in edges
      try
        {fid} = await t.one rem_edge, {edge_id}
      catch err
        console.error "#{edge_id} ".red.bold+"#{err}".slice(7).red.dim

    await proc('procedures/clean-topology-02')

cleanTopology = ->

  await deleteEdges()

  await db.task (t)->
    console.log "Healing edges".green.bold

    n = 100
    counter = 0
    while n > 0
      res = await t.query sql('procedures/get-edges-to-heal')
      n = res.length
      for {edge1,edge2} in res
        if global.verbose
          console.log "Healing edges "+String(edge1).green+" and "+String(edge2).green
        try
          console.log edge1,edge2
          t.one sql('procedures/clean-topology-heal-edge'), {edge1,edge2}
          counter += 1
        catch err
          console.log "#{err.message}".red.dim

    console.log "Healed #{counter} edges"

handler = ->
  await cleanTopology()
  process.exit()

module.exports = {command, describe,
                  handler, cleanTopology, deleteEdges}

