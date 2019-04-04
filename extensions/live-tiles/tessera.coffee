'use strict'
crypto = require('crypto')
path = require('path')
url = require('url')
util = require('util')
cachecache = require('cachecache')
clone = require('clone')
debug = require('debug')
express = require('express')
handlebars = require('handlebars')
mercator = new (require('@mapbox/sphericalmercator'))
debug = debug('tessera')
FLOAT_PATTERN = '[+-]?(?:\\d+|\\d+.?\\d+)'
SCALE_PATTERN = '@[23]x'
# TODO a more complete implementation of this exists...somewhere

getInfo = (source, callback) ->
  source.getInfo (err, _info) ->
    if err
      return callback(err)
    info = {}
    Object.keys(_info).forEach (key) ->
      info[key] = _info[key]
      return
    info.name = info.name or 'Untitled'
    info.center = info.center or [
      -122.4440
      37.7908
      12
    ]
    info.bounds = info.bounds or [
      -180
      -85.0511
      180
      85.0511
    ]
    info.format = info.format or 'png'
    info.minzoom = Math.max(0, info.minzoom | 0)
    info.maxzoom = info.maxzoom or Infinity
    if info.vector_layers
      info.format = 'pbf'
    callback null, info

getExtension = (format) ->
  # trim PNG variant info
  switch (format or '').replace(/^(png).*/, '$1')
    when 'png'
      return 'png'
    else
      return format
  return

getScale = (scale) ->
  (scale or '@1x').slice(1, 2) | 0

normalizeHeaders = (headers) ->
  _headers = {}
  Object.keys(headers).forEach (x) ->
    _headers[x.toLowerCase()] = headers[x]
    return
  _headers

md5sum = (data) ->
  hash = crypto.createHash('md5')
  hash.update data
  hash.digest()

module.exports = (tilelive, options) ->
  app = express().disable('x-powered-by').enable('trust proxy')
  templates = {}
  uri = options
  staticMap = true
  tilePath = '/{z}/{x}/{y}.{format}'
  sourceMaxZoom = null
  tilePattern = undefined
  app.use cachecache()
  if typeof options == 'object'
    uri = options.source
    tilePath = options.tilePath or tilePath
    staticMap = options.staticMap or staticMap
    if options.sourceMaxZoom
      sourceMaxZoom = parseInt(options.sourceMaxZoom)
    Object.keys(options.headers or {}).forEach (name) ->
      templates[name] = handlebars.compile(options.headers[name])
      # attempt to parse so we can fail fast
      try
        templates[name]()
      catch e
        console.error '\'%s\' header is invalid:', name
        console.error e.message
        process.exit 1
      return
  if typeof uri == 'string'
    uri = url.parse(uri, true)
  else
    uri = clone(uri)
  tilePattern = tilePath.replace(/\.(?!.*\.)/, ':scale(' + SCALE_PATTERN + ')?.').replace(/\./g, '.').replace('{z}', ':z(\\d+)').replace('{x}', ':x(\\d+)').replace('{y}', ':y(\\d+)').replace('{format}', ':format([\\w\\.]+)')

  populateHeaders = (headers, params, extras) ->
    Object.keys(extras or {}).forEach (k) ->
      params[k] = extras[k]
      return
    Object.keys(templates).forEach (name) ->
      val = templates[name](params)
      if val
        headers[name.toLowerCase()] = val
      return
    headers

  # warm the cache
  tilelive.load uri
  sourceURIs = 1: uri
  [2,3].forEach (scale) ->
    retinaURI = clone(uri)
    retinaURI.query.scale = scale
    # explicitly tell tilelive-mapnik to use larger tiles
    retinaURI.query.tileSize = scale * 256
    sourceURIs[scale] = retinaURI
    return

  getTile = (z, x, y, scale, format, callback) ->
    sourceURI = sourceURIs[scale]
    params = tile:
      zoom: z
      x: x
      y: y
      format: format
      retina: scale > 1
      scale: scale
    # Additional params for vector tile based sources
    if sourceMaxZoom != null
      params.tile.sourceZoom = z
      params.tile.sourceX = x
      params.tile.sourceY = y
      while params.tile.sourceZoom > sourceMaxZoom
        params.tile.sourceZoom--
        params.tile.sourceX = Math.floor(params.tile.sourceX / 2)
        params.tile.sourceY = Math.floor(params.tile.sourceY / 2)
    tilelive.load sourceURI, (err, source) ->
      if err
        return callback(err)
      getInfo source, (err, info) ->
        if err
          return callback(err)
        # validate format / extension
        ext = getExtension(info.format)
        if ext != format
          debug 'Invalid format \'%s\', expected \'%s\'', format, ext
          return callback(null, null, populateHeaders({}, params,
            404: true
            invalidFormat: true))
        # validate zoom
        if z < info.minzoom or z > info.maxzoom
          debug 'Invalid zoom:', z
          return callback(null, null, populateHeaders({}, params,
            404: true
            invalidZoom: true))
        # validate coords against bounds
        xyz = mercator.xyz(info.bounds, z)
        if x < xyz.minX or x > xyz.maxX or y < xyz.minY or y > xyz.maxY
          debug 'Invalid coordinates: %d,%d relative to bounds:', x, y, xyz
          return callback(null, null, populateHeaders({}, params,
            404: true
            invalidCoordinates: true))
        source.getTile z, x, y, (err, data, headers) ->
          headers = normalizeHeaders(headers or {})
          if err
            if err.message.match(/(Tile|Grid) does not exist/)
              return callback(null, null, populateHeaders(headers, params, 404: true))
            return callback(err)

          if not data?
            return callback(null, null, populateHeaders(headers, params, 404: true))

          headers['content-md5'] ?= md5sum(data).toString('base64')

          callback null, data, populateHeaders(headers, params, 200: true)

  app.get tilePattern, (req, res, next) ->
    z = req.params.z | 0
    x = req.params.x | 0
    y = req.params.y | 0
    scale = getScale(req.params.scale)
    format = req.params.format
    getTile z, x, y, scale, format, ((err, data, headers) ->
      if err
        return next(err)
      if data == null
        res.status(404).send 'Not found'
      else
        res.set headers
        res.status(200).send data
    ), res, next

  return app

# ---
# generated by js2coffee 2.2.0
