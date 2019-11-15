socketIO = require 'socket.io'

topologyWatcher = (db, server)->
  console.log 'Starting topology watcher'
  io = socketIO(server)
  io.on 'connection', ->
    console.log "Client connected"

  # Listen for data
  conn = await db.connect {direct: true}
  conn.client.on 'notification', (message)->
    data = JSON.parse(message.payload)
    io.emit "topology", data
    console.log "Topology: #{data.payload}"

  conn.none('LISTEN $1~', 'topology')

module.exports = {topologyWatcher}
