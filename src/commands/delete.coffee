{prompt} = require 'inquirer'
{proc} = require '../util'

command = 'delete'
describe = 'Delete the map topology'
handler = (argv)->
  res = await prompt [{
    type: 'boolean'
    name: 'shouldDelete'
    message: 'Do you really want to delete the topology?',
  }]
  await proc('procedures/delete-topology.sql')
  process.exit()

module.exports = {command, describe, handler}
