{prompt} = require 'inquirer'
{proc} = require '../util'

command = 'reset'
describe = 'Reset the map topology'
handler = (argv)->
  res = await prompt [{
    type: 'boolean'
    name: 'shouldReset'
    message: 'Do you really want to reset the topology?',
  }]
  await proc('topology/procedures/reset-topology.sql')
  process.exit()

module.exports = {command, describe, handler}

