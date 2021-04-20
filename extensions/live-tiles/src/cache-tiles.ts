/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS202: Simplify dynamic range loops
 * DS205: Consider reworking code to avoid use of IIFEs
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const SphericalMercator = require('@mapbox/sphericalmercator');
const Promise = require('bluebird');

const {tileFactory} = require('./tile-factory');
const cfg = require('../../../src/config');

const command = 'cache-tiles [--all]';
const describe = 'Cache tile layers';

const merc = new SphericalMercator({size: 256});

const tileCoords = function*(zoomLevels, bounds){
  return yield* (function*() {
    const result = [];
    for (var z of Array.from(zoomLevels)) {
      var {minX, maxX, minY, maxY} = merc.xyz(bounds, z);
      result.push(yield* (function*() {
        const result1 = [];
        for (var x = minX, end = maxX, asc = minX <= end; asc ? x <= end : x >= end; asc ? x++ : x--) {
          result1.push(yield* (function*() {
            const result2 = [];
            for (let y = minY, end1 = maxY, asc1 = minY <= end1; asc1 ? y <= end1 : y >= end1; asc1 ? y++ : y--) {
              result2.push(yield {z,x,y});
            }
            return result2;
          }).call(this));
        }
        return result1;
      }).call(this));
    }
    return result;
  }).call(this);
};

const handler = async function() {

  const {layers, bounds, zoomRange} = cfg['live-tiles'];
  const zoomLevels = __range__(zoomRange[0], zoomRange[1], true);

  let total = 0;
  for (let z of Array.from(zoomLevels)) {
    const {minX, maxX, minY, maxY} = merc.xyz(bounds, z);
    const n = (maxX-minX)*(maxY-minY);
    total += n;
    console.log(`zoom ${z}: ${n} tiles`);
  }
  console.log(`  total: ${total} tiles`);


  return await (async () => {
    const result = [];
    for (let name in layers) {
      const lyr = layers[name];
      var getTile = await tileFactory(lyr);
      const coords = tileCoords(zoomLevels, bounds);
      const fn = async ({z,x,y}) => await getTile(z,x,y);

      result.push(Promise.mapSeries(coords, fn, {concurrency: 8}));
    }
    return result;
  })();
};

module.exports = {command, describe, handler};


function __range__(left, right, inclusive) {
  let range = [];
  let ascending = left < right;
  let end = !inclusive ? right : ascending ? right + 1 : right - 1;
  for (let i = left; ascending ? i < end : i > end; ascending ? i++ : i--) {
    range.push(i);
  }
  return range;
}