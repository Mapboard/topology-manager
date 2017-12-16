#!/usr/bin/env coffee
{proc} = require '../util'
colors = require 'colors'

command = 'clean-topology'
describe = 'Clean topology'

cleanTopology = ->
  await proc('procedures/clean-topology.sql')

handler = ->
  await cleanTopology()
  process.exit()

module.exports = {command, describe,
                  handler, cleanTopology}

