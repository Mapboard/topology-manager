/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
"use strict";
const crypto = require("crypto");
const path = require("path");
const url = require("url");
const util = require("util");
const cachecache = require("cachecache");
const clone = require("clone");
let debug = require("debug");
const express = require("express");
const handlebars = require("handlebars");
const mercator = new (require("@mapbox/sphericalmercator"))();
debug = debug("tessera");
const FLOAT_PATTERN = "[+-]?(?:\\d+|\\d+.?\\d+)";
const SCALE_PATTERN = "@[23]x";
// TODO a more complete implementation of this exists...somewhere

const getInfo = (source, callback) =>
  source.getInfo(function (err, _info) {
    if (err) {
      return callback(err);
    }
    const info = {};
    Object.keys(_info).forEach(function (key) {
      info[key] = _info[key];
    });
    info.name = info.name || "Untitled";
    info.center = info.center || [-122.444, 37.7908, 12];
    info.bounds = info.bounds || [-180, -85.0511, 180, 85.0511];
    info.format = info.format || "png";
    info.minzoom = Math.max(0, info.minzoom | 0);
    info.maxzoom = info.maxzoom || Infinity;
    if (info.vector_layers) {
      info.format = "pbf";
    }
    return callback(null, info);
  });

const getExtension = function (format) {
  // trim PNG variant info
  switch ((format || "").replace(/^(png).*/, "$1")) {
    case "png":
      return "png";
      break;
    default:
      return format;
  }
};

const getScale = (scale) => (scale || "@1x").slice(1, 2) | 0;

const normalizeHeaders = function (headers) {
  const _headers = {};
  Object.keys(headers).forEach(function (x) {
    _headers[x.toLowerCase()] = headers[x];
  });
  return _headers;
};

const md5sum = function (data) {
  const hash = crypto.createHash("md5");
  hash.update(data);
  return hash.digest();
};

module.exports = function (tilelive, options) {
  const app = express().disable("x-powered-by").enable("trust proxy");
  const templates = {};
  let uri = options;
  let staticMap = true;
  let tilePath = "/{z}/{x}/{y}.{format}";
  let sourceMaxZoom = null;
  let tilePattern = undefined;
  app.use(cachecache());
  if (typeof options === "object") {
    uri = options.source;
    tilePath = options.tilePath || tilePath;
    staticMap = options.staticMap || staticMap;
    if (options.sourceMaxZoom) {
      sourceMaxZoom = parseInt(options.sourceMaxZoom);
    }
    Object.keys(options.headers || {}).forEach(function (name) {
      templates[name] = handlebars.compile(options.headers[name]);
      // attempt to parse so we can fail fast
      try {
        templates[name]();
      } catch (e) {
        console.error("'%s' header is invalid:", name);
        console.error(e.message);
        process.exit(1);
      }
    });
  }
  if (typeof uri === "string") {
    uri = url.parse(uri, true);
  } else {
    uri = clone(uri);
  }
  tilePattern = tilePath
    .replace(/\.(?!.*\.)/, ":scale(" + SCALE_PATTERN + ")?.")
    .replace(/\./g, ".")
    .replace("{z}", ":z(\\d+)")
    .replace("{x}", ":x(\\d+)")
    .replace("{y}", ":y(\\d+)")
    .replace("{format}", ":format([\\w\\.]+)");

  const populateHeaders = function (headers, params, extras) {
    Object.keys(extras || {}).forEach(function (k) {
      params[k] = extras[k];
    });
    Object.keys(templates).forEach(function (name) {
      const val = templates[name](params);
      if (val) {
        headers[name.toLowerCase()] = val;
      }
    });
    return headers;
  };

  // warm the cache
  tilelive.load(uri);
  const sourceURIs = { 1: uri };
  [2, 3].forEach(function (scale) {
    const retinaURI = clone(uri);
    retinaURI.query.scale = scale;
    // explicitly tell tilelive-mapnik to use larger tiles
    retinaURI.query.tileSize = scale * 256;
    sourceURIs[scale] = retinaURI;
  });

  const getTile = function (z, x, y, scale, format, callback) {
    const sourceURI = sourceURIs[scale];
    const params = {
      tile: {
        zoom: z,
        x,
        y,
        format,
        retina: scale > 1,
        scale,
      },
    };
    // Additional params for vector tile based sources
    if (sourceMaxZoom !== null) {
      params.tile.sourceZoom = z;
      params.tile.sourceX = x;
      params.tile.sourceY = y;
      while (params.tile.sourceZoom > sourceMaxZoom) {
        params.tile.sourceZoom--;
        params.tile.sourceX = Math.floor(params.tile.sourceX / 2);
        params.tile.sourceY = Math.floor(params.tile.sourceY / 2);
      }
    }
    return tilelive.load(sourceURI, function (err, source) {
      if (err) {
        return callback(err);
      }
      return getInfo(source, function (err, info) {
        if (err) {
          return callback(err);
        }
        // validate format / extension
        const ext = getExtension(info.format);
        if (ext !== format) {
          debug("Invalid format '%s', expected '%s'", format, ext);
          return callback(
            null,
            null,
            populateHeaders({}, params, {
              404: true,
              invalidFormat: true,
            })
          );
        }
        // validate zoom
        if (z < info.minzoom || z > info.maxzoom) {
          debug("Invalid zoom:", z);
          return callback(
            null,
            null,
            populateHeaders({}, params, {
              404: true,
              invalidZoom: true,
            })
          );
        }
        // validate coords against bounds
        const xyz = mercator.xyz(info.bounds, z);
        if (x < xyz.minX || x > xyz.maxX || y < xyz.minY || y > xyz.maxY) {
          debug("Invalid coordinates: %d,%d relative to bounds:", x, y, xyz);
          return callback(
            null,
            null,
            populateHeaders({}, params, {
              404: true,
              invalidCoordinates: true,
            })
          );
        }
        return source.getTile(z, x, y, function (err, data, headers) {
          headers = normalizeHeaders(headers || {});
          if (err) {
            if (err.message.match(/(Tile|Grid) does not exist/)) {
              return callback(
                null,
                null,
                populateHeaders(headers, params, { 404: true })
              );
            }
            return callback(err);
          }

          if (data == null) {
            return callback(
              null,
              null,
              populateHeaders(headers, params, { 404: true })
            );
          }

          if (headers["content-md5"] == null) {
            headers["content-md5"] = md5sum(data).toString("base64");
          }

          return callback(
            null,
            data,
            populateHeaders(headers, params, { 200: true })
          );
        });
      });
    });
  };

  app.get(tilePattern, function (req, res, next) {
    const z = req.params.z | 0;
    const x = req.params.x | 0;
    const y = req.params.y | 0;
    const scale = getScale(req.params.scale);
    const { format } = req.params;
    return getTile(
      z,
      x,
      y,
      scale,
      format,
      function (err, data, headers) {
        if (err) {
          return next(err);
        }
        if (data === null) {
          return res.status(404).send("Not found");
        } else {
          res.set(headers);
          return res.status(200).send(data);
        }
      },
      res,
      next
    );
  });

  return app;
};

// ---
// generated by js2coffee 2.2.0
