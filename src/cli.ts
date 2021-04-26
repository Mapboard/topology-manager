/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
import yargs from "yargs";
import { spawnSync } from "child_process";
const { join, resolve } = require("path");
const { existsSync } = require("fs");
const colors = require("colors");
const external = function (cmd, describe) {
  if (describe == null) {
    describe = "";
  }
  const cmdStart = cmd.split(" ")[0];
  const prefixedCommand = `geologic-map-${cmdStart}`;
  const command = cmd;

  const handler = function (argv) {
    // See if this is available locally, if not, search
    // on path.
    const fp = join(__dirname, prefixedCommand);
    const v = process.argv.slice(3);
    return spawnSync(prefixedCommand, v, { stdio: "inherit" });
  };
  return { command, describe, handler };
};

/* Create extension commands from config */
const createExtensionCommands = function (argv) {
  // Set verbosity
  global.verbose = argv.argv.verbose;
  const config = require("../src/config");
  global.config = config;
  for (let ext of Array.from(config.extensions)) {
    if (ext.commands == null) {
      ext.commands = [];
    }
    for (let commandFile of Array.from(ext.commands)) {
      commandFile = join(ext.path, commandFile);
      const cmd = require(commandFile);
      argv.command(cmd);
    }
  }
  return argv;
};

const argv = yargs
  .usage("geologic-map <command>")
  .option("c", {
    description: `JSON config file. Used in lieu of the \
GEOLOGIC_MAP_CONFIG environment variable`,
  })
  .option("verbose", {
    alias: "v",
    description: "Increase verbosity",
    global: true,
  })
  .command(external("set-colors [file]", "Set colors from csv file (id,color)"))
  .command(
    external(
      "config [sub.item]",
      "Show configuration, optionally fetching a specific value"
    )
  )
  .command(require("../src/commands/update-contacts"))
  .command(require("../src/commands/update-faces"))
  .command(require("../src/commands/update"))
  .command(require("../src/commands/create-tables"))
  .command(require("../src/commands/reset"))
  .command(require("../src/commands/delete"))
  .command(require("../src/commands/clean-topology"))
  .command(require("../extensions/server/command"))
  .wrap(null);

createExtensionCommands(argv).demandCommand().argv;
