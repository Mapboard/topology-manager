/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const {updateContacts} = require('./update-contacts');
const {updateFaces} = require('./update-faces');
const {cleanTopology} = require('./clean-topology');
const {db} = require('../util');
const colors = require('colors');

const command = 'update [--reset] [--fill-holes] [--watch] [--fix-failed]';
const describe = 'Update topology';

const updateAll = async function(opts={}){
  let {verbose, reset, fillHoles, fixFailed} = opts;
  if (reset == null) { reset = false; }
  if (verbose == null) { verbose = false; }
  if (fillHoles == null) { fillHoles = false; }

  console.time('update');
  try {
    console.log("Updating contacts".green.bold);
    await updateContacts({fixFailed});
    console.log("Updating faces".green.bold);
    await updateFaces({reset, fillHoles});
    console.log("Cleaning topology".green.bold);
    await cleanTopology();
  } catch (err) {
    console.error(err);
  }
  return console.timeEnd('update');
};

const startWatcher = async function() {
  let updateInProgress = false;
  let needsUpdate = true;
  const runCommand = async () => {
    if (updateInProgress) { return; }
    if (!needsUpdate) { return; }

    updateInProgress = true;
    needsUpdate = false;
    await updateAll();
    return updateInProgress = false;
  };

  const conn = await db.connect({direct: true});
  conn.client.on('notification', data => needsUpdate = true);

  conn.none('LISTEN $1~', 'events');
  // Poll every second to see if we need to do things
  return setInterval(runCommand, 1000);
};


const handler = async function(argv){
  if (argv.watch) {
    startWatcher();
    return;
  }
  const {reset, fillHoles} = argv;
  await updateAll({reset,fillHoles});
  return process.exit();
};

module.exports = {command, describe, handler, startWatcher, updateAll};
