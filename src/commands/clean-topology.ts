#!/usr/bin/env node
/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const {proc, db, sql} = require('../util');
const colors = require('colors');

const command = 'clean-topology';
const describe = 'Clean topology';

const deleteEdges = async function() {
  const rem_edge = sql('procedures/clean-topology-rem-edge');
  await proc('procedures/clean-topology-01');
  return await db.task(async function(t){
    console.log("Deleting edges".green.bold);
    const edges = await db.query(sql('procedures/get-edges-to-delete'));
    for (let {edge_id} of Array.from(edges)) {
      try {
        const {fid} = await t.one(rem_edge, {edge_id});
      } catch (err) {
        console.error(`${edge_id} `.red.bold+`${err}`.slice(7).red.dim);
      }
    }

    return await proc('procedures/clean-topology-02');
  });
};

const cleanTopology = async function() {

  await deleteEdges();

  return await db.task(async function(t){
    console.log("Healing edges".green.bold);

    let n = 10;
    let counter = 0;
    while (n > 0) {
      const res = await t.query(sql('procedures/get-edges-to-heal'));
      n = res.length;
      for (let {edge1,edge2} of Array.from(res)) {
        if (global.verbose) {
          console.log("Healing edges "+String(edge1).green+" and "+String(edge2).green);
        }
        try {
          console.log(edge1,edge2);
          t.one(sql('procedures/clean-topology-heal-edge'), {edge1,edge2});
          counter += 1;
        } catch (err) {
          console.log(`${err.message}`.red.dim);
        }
      }
    }

    return console.log(`Healed ${counter} edges`);
  });
};

const handler = async function() {
  await cleanTopology();
  return process.exit();
};

module.exports = {command, describe,
                  handler, cleanTopology, deleteEdges};

