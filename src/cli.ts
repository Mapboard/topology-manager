/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const yargs = require("yargs/yargs");
import { spawnSync } from "child_process";
const { join } = require("path");
const config = require("./config");

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
  const config = require("./config");
  global.config = config;
  for (const ext of config.extensions) {
    const { commands = [] } = ext;

    for (const commandFile of commands) {
      const cmd = require(join(ext.path, commandFile));
      argv = argv.command(cmd);
    }
  }
  return argv;
};

const configCommand = {
  command: "config [sub.item]",
  describe: "Show configuration, optionally fetching a specific value",
  handler(argv) {
    if (argv._.length === 2) {
      const args: string[] = argv._[1].split(".");
      let v = config;
      for (const arg of Array.from(args)) {
        v = v[arg];
      }
      console.log(v);
    } else {
      console.log(config);
    }
  },
};

const cli = yargs(process.argv.slice(2));

cli
  .scriptName(config.commandName)
  .usage(config.commandName + ` <command>`)
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
  .command(require("./commands/update-contacts"))
  .command(require("./commands/update-faces"))
  .command(require("./commands/update"))
  .command(require("./commands/create-tables"))
  .command(require("./commands/reset"))
  .command(require("./commands/delete"))
  .command(require("./commands/clean-topology"))
  .command(require("./server"))
  .command(configCommand)
  .wrap(cli.terminalWidth()); //.exitProcess(false);

createExtensionCommands(cli).demandCommand().help();

cli.argv;
