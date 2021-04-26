const { prompt } = require("inquirer");
const { proc } = require("../util");

const command = "delete";
const describe = "Delete the map topology";
const handler = async function (argv) {
  const res = await prompt([
    {
      type: "boolean",
      name: "shouldDelete",
      message: "Do you really want to delete the topology?",
    },
  ]);
  await proc("procedures/delete-topology.sql");
  return process.exit();
};

module.exports = { command, describe, handler };
