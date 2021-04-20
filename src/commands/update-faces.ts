/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const ProgressBar = require('progress');
const {db,sql, proc} = require('../util');
const {deleteEdges} = require('./clean-topology');

const count = "SELECT count(*)::integer nfaces FROM map_topology.__dirty_face";
const command = 'update-faces [--reset] [--fill-holes]';
const describe = 'Update map faces';

const updateFaces = async function(opts={}){
  let {reset, fillHoles} = opts;
  if (reset == null) { reset = false; }
  if (fillHoles == null) { fillHoles = false; }

  if (reset) {
    await proc("procedures/reset-map-face");
  }

  if (fillHoles) {
    await proc("procedures/set-holes-as-dirty");
  }

  await proc("procedures/prepare-update-face");

  console.time("Updating faces");
  let {nfaces} = await db.one(count);
  if (nfaces === 0) {
    console.log("No faces to update");
    return;
  }
  const bar = new ProgressBar('Updating faces :bar :current/:total (:eta s)', { total: nfaces });
  bar.tick(0);
  while (nfaces > 0) {
    await db.query("SELECT map_topology.update_map_face()");
    const {nfaces: next} = await db.one(count);
    bar.tick(nfaces-next);
    nfaces = next;
  }
  return console.timeEnd("Updating faces");
};

const handler = async function(argv){
  await updateFaces(argv);
  return process.exit();
};

const builder = function(yargs){
  yargs
    .option('fill-holes', {default: false, description: 'Try to fill all holes'})
    .option('reset', {default: false, description: 'Rebuild from scratch'});
  return yargs;
};

module.exports = {command, describe, handler, builder, updateFaces};

