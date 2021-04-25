/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS205: Consider reworking code to avoid use of IIFEs
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const glob = require('glob-promise');
const {__base, proc} = require('../util');
const {extensions: allExtensions} = require('../config');
const {join} = require('path');
const colors = require('colors');

const command = 'create-tables [--core] [--extensions] [--extension EXT] [--all]';
const describe = 'Create tables';

const createCoreTables = async function() {
  let fn;
  for (fn of Array.from(await glob('fixtures/*.sql', {cwd: __base}))) {
    await proc(fn);
  }

  // These should really be handled by extensions
  for (fn of Array.from(await glob('extensions/server/fixtures/*.sql', {cwd: __base}))) {
    await proc(fn);
  }
  return await proc('extensions/map-digitizer.sql');
};

const createExtensionTables = async function(e){
  let __dir;
  let {fixtures, path} = e;
  if (!fixtures) { return; }
  console.log("Extension "+e.name.green.bold);
  console.log(e.description.green.dim);
  console.log("at: ".grey + e.path.green);
  console.log("");
  if (typeof fixtures === 'string') {
    __dir = join(path, fixtures);
    fixtures = await glob('*.sql', {cwd: __dir});
  }
  return await (async () => {
    const result = [];
    for (let fn of Array.from(fixtures)) {
      const p = join(__dir, fn);
      result.push(await proc(p, {trimPath: e.path, indent: "    "}));
    }
    return result;
  })();
};

const handler = async function(argv){

  let {extensions, extension, core, all} = argv;

  // Set variables properly
  if (extensions == null) { extensions = false; }
  if (core == null) { core = false; }
  if (all == null) { all = false; }
  if (all) {
    core = true;
    extensions = true;
  }

  if (!(extensions || core || extension)) {
    console.log(`Please specify --extensions, --core, or --all, \
or a specific extension with --extension`
    );
    process.exit(0);
  }
  try {
    if (core) { await createCoreTables(); }

    // Figure out which extensions we need to run
    let runExtensions = [];
    if (extensions) {
      runExtensions = allExtensions;
    } else if (extension) {
      runExtensions = allExtensions.filter(d => d.name === extension);
    }

    for (let e of Array.from(runExtensions)) {
      await createExtensionTables(e);
    }

  } catch (err) {
    console.log(`${err.stack}`.red);
    process.exit();
  }
  return process.exit();
};

module.exports = {command, describe, handler, createCoreTables};
