UDP = require("dgram")
TCP = require("net")
Network = require("network")
EventEmitter = require("events").EventEmitter

class Peer extends EventEmitter
  constructor: (@host, @socket) ->
    @ack = {
      requests: 0 # sent requests
      acked: false # not connected
    }

    @ackInterval = null

  initialize: () ->
    @ackInterval = setInterval(@connectionHandler, 250)

  connectionHandler: () =>
    @send({
      request: "ack"
      status: 200
    })
    @ack.requests++

    if @ack.requests > 10 # lost connection
      clearInterval(@ackInterval)
      if @ack.acked
        @emit("disconnect", @)

  receive: (data) =>
    if data.request is "ack"
      if not @ack.acked
        @ack.acked = true
        @emit("connect", @)

      @ack.requests = 0 #reset ack
    else
      @emit("data", @, data)

  send: (data, done) =>
    data = new Buffer(JSON.stringify(data))

    @socket.send data, 0, data.length, @host.private.port, @host.private.address, (err, bytes) ->
      if err?
        socket.close()
      else
        callback() if callback?

class UDPHoleClient extends EventEmitter
  constructor: (options) ->
    options.port = options.port || 1338
    options.host = options.host || "127.0.0.1"

    @privateAddress = null # will be calculated when started
    @server = {
      port: options.port
      address: options.host
    }

    throw new Error("Service now set") if not options.service?
    @service = options.service

    @socket = UDP.createSocket("udp4")
    @peers = [] # hosts that are punched

  initProtocol: (done) =>
    @socket.on "message", (encodedData, publicInfo) =>
      try
        data = JSON.parse(encodedData)
      catch e
        return console.log("Cannot parse given data #{e}: #{data}")

      if data.request not in ["connect", "register", "heartbeat", "bye"]
        return @getPeer(publicInfo).receive(data)

      if data.status isnt 200
        return @emit("fail", data.request, data.status, data.message)

      if data.request is "heartbeat"
        return @sendToHost(publicInfo, data)

      # new connection was received, add it to hosts
      if data.request is "connect"
        for connection in data.hosts
          peer = new Peer(connection, @socket)
          @peers.push(peer) # push newly connected connection

          peer.initialize()

          peer.on "disconnect", (peer) =>
            @peers.splice(@peers.indexOf(peer), 1) # remove from peers
            @emit("disconnect", peer)

          peer.on "connect", (peer) =>
            @emit("connect", peer)

          peer.on "data", (peer, data) =>
            @emit("data", peer, data)

      if data.request is "register" and data.status is 200
        console.log "Registration of service \'#{@service.name}\' successful"

    @socket.on "listening", () =>
      request = {
        service: @service
        private: {
          port: @socket.address().port
          address: @privateAddress
        }
      }

      if @service.host is true
        @sendToServer("register", 200, request)
      else
        @sendToServer("connect", 200, request)

    Network.get_private_ip (err, ip) =>
      @privateAddress = ip
      done(err)

  getPeer: (host) =>
    for peer in @peers
      if peer.host.private.port is host.port and peer.host.private.address is host.address
        return peer

    return null

  # sends data to the hole service server
  sendToServer: (request, status, data, done) =>
    data.request = data.request || request
    data.status = data.status || status
    @sendToHost(@server, data, done)

  # sends data to the specified host
  sendToHost: (host, data, done) =>
    data = new Buffer(JSON.stringify(data))

    @socket.send data, 0, data.length, host.port, host.address, (err, bytes) ->
      if err?
        socket.close()
      else
        callback() if callback?

  # sends data to all connections
  send: (data, done) =>
    for peer in @peers
      peer.send(data, done)

  start: () =>
    @socket.removeAllListeners() # clear listeners on socket
    @initProtocol (err) =>
      @socket.bind() # bind socket


module.exports.create = (options) ->
  return new UDPHoleClient(options)