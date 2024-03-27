const { prompt } = require("inquirer");
const { proc } = require("../util");

const command = "reset";
const describe = "Reset the map topology";
const handler = async function (argv) {
  const res = await prompt([
    {
      type: "boolean",
      name: "shouldReset",
      message: "Do you really want to reset the topology?",
    },
  ]);
  await proc("procedures/reset-topology.sql");
  return process.exit();
};

module.exports = { command, describe, handler };
