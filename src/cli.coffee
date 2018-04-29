#!/usr/bin/env coffee
yargs = require 'yargs'
{spawnSync} = require 'child_process'
{join, resolve} = require 'path'
{existsSync} = require 'fs'
colors = require 'colors'
external = (cmd, describe="")->
  cmdStart = cmd.split(' ')[0]
  prefixedCommand = "geologic-map-#{cmdStart}"
  command = cmd

  handler = (argv)->
    # See if this is available locally, if not, search
    # on path.
    fp = join __dirname, prefixedCommand
    prefixedCommand = fp if existsSync fp
    spawnSync prefixedCommand, argv._.slice(1), {stdio: 'inherit'}
  return {command, describe, handler}

### Create extension commands from config ###
createExtensionCommands = (argv)->
  # Set verbosity
  global.verbose = argv.argv.verbose
  config = require '../src/config'
  global.config = config
  for ext in config.extensions
    ext.commands ?= []
    for commandFile in ext.commands
      commandFile = join(ext.path, commandFile)
      cmd = require commandFile
      argv.command cmd
  return argv

argv = yargs
  .usage 'geologic-map <command>'
  .option 'c', {
    description: "JSON config file. Used in lieu of the
                  GEOLOGIC_MAP_CONFIG environment variable"}
  .option 'verbose', {
    alias: 'v'
    description: "Increase verbosity"
    global: true
    }
  .command external 'set-colors [file]', 'Set colors from csv file (id,color)'
  .command external 'config [sub.item]', 'Show configuration, optionally fetching a specific value'
  .command require '../src/commands/update-contacts'
  .command require '../src/commands/update-faces'
  .command require '../src/commands/update'
  .command require '../src/commands/create-tables'
  .command require '../src/commands/reset'
  .command require '../src/commands/delete'
  .command require '../src/commands/clean-topology'
  .command require '../extensions/server/command'
  .wrap null

createExtensionCommands(argv)
  .demandCommand()
  .argv

