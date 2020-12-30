glob = require 'glob-promise'
{__base, proc} = require '../util'
{extensions: allExtensions} = require '../config'
{join} = require 'path'
colors = require 'colors'

command = 'create-tables [--core] [--extensions] [--extension EXT] [--all]'
describe = 'Create tables'

createCoreTables = ->
  for fn in await glob('fixtures/*.sql', cwd: __base)
    await proc(fn)
  await proc('extensions/map-digitizer.sql')

createExtensionTables = (e)->
  {fixtures, path} = e
  return unless fixtures
  console.log "Extension "+e.name.green.bold
  console.log e.description.green.dim
  console.log "at: ".grey + e.path.green
  console.log ""
  if typeof fixtures == 'string'
    __dir = join(path, fixtures)
    fixtures = await glob('*.sql', cwd: __dir)
  for fn in fixtures
    p = join __dir, fn
    await proc(p, {trimPath: e.path, indent: "    "})

handler = (argv)->

  {extensions, extension, core, all} = argv

  # Set variables properly
  extensions ?= false
  core ?= false
  all ?= false
  if all
    core = true
    extensions = true

  if not (extensions or core or extension)
    console.log "Please specify --extensions, --core, or --all,
                 or a specific extension with --extension"
    process.exit 0
  try
    await createCoreTables() if core

    # Figure out which extensions we need to run
    runExtensions = []
    if extensions
      runExtensions = allExtensions
    else if extension
      runExtensions = allExtensions.filter (d)->
        d.name == extension

    for e in runExtensions
      await createExtensionTables(e)

  catch err
    console.log "#{err.stack}".red
    process.exit()
  process.exit()

module.exports = {command, describe, handler, createCoreTables}
