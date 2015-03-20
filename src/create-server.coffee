UDP = require("dgram")

class Listener
  constructor: (@port, @host = "0.0.0.0") ->
    @socket = UDP.createSocket("udp4")

  listen: () =>
    @socket.bind(@port, @host)

  send: (host, data, done) ->
    encodedData = new Buffer(JSON.stringify(data))

    @socket.send encodedData, 0, encodedData.length, host.port, host.address, done

class Service
  constructor: (@listener, @name, @type = "single") ->
    # private information about hosts
    # { private: {}, public: {} }
    @hosts = []

    @heartbeatInterval = setInterval () =>
      @broadcastHosts "heartbeat", 200, {}
    , 2500

  addHost: (privateInfo, publicInfo) =>
    @broadcastHosts("connect", 200, {
      hosts: [{
        private: privateInfo # needed for punch
        public: publicInfo # just so we can explore previous communication
      }]
    })

    @send(publicInfo, "connect", 200, {
      hosts: @hosts
    })

    # add new host only if swarm or none in single service
    if (@type is "single" and @hosts.length is 0) or (@type is "swarm") 
      @hosts.push({ private: privateInfo, public: publicInfo})
      console.log "Host added to service \'#{@name}\'"

  broadcastHosts: (request, status, data, done) =>
    for connection in @hosts
      host = connection.private # get private data from host
      @send(host, request, status, data, done)

  send: (host, request, status, data, done) ->
    # join status and request into the data block
    data.status = status || data.status
    data.request = request || data.request

    @listener.send(host, data, done)

  start: () =>
    @listener.socket.bind(@l)

class UDPHoleService
  constructor: (@options) ->
    # key = name, value = Service
    @services = { }

    @options.port = @options.port || 1338
    @options.host = @options.host || "0.0.0.0"

    @listener = @createListener(@options.port, @options.host)
    @initProtocol()

  initProtocol: () =>
    @listener.socket.on "message", (encodedData, publicInfo) =>
      try
        data = JSON.parse(encodedData)
        @validateMessage(data)
      catch ex
        return console.log("Exception occured during parse: #{ex.message}")

      @handleServiceRegistration(data, publicInfo) if data.request is "register"
      @handleServiceConnection(data, publicInfo) if data.request is "connect"

  validateMessage: (json) ->
    if not json?
      throw new Error("Invalid json specified")

    if not json.request?
      throw new Error("Request is missing \'request\' attribute")

    if not json.status?
      throw new Error("Request is missing \'status\' attribute")

  handleServiceRegistration: (data, publicInfo) =>
    service = @services[data.service.name]
    if not service?
      # validate data type
      data.service.type = data.service.type || "single"
      data.service.host = data.service.host || true

      @service(data.service.name, data.service.type).addHost(data.private, publicInfo)

      @send(publicInfo, "register", 200, {
        message: "up"
      })
    else
      @send(publicInfo, "register", 409, {
        message: "Service already registered"
      })

  handleServiceConnection: (data, publicInfo) =>
    data.service.type = data.service.type || "single"

    service = @services[data.service.name]
    if service? and service.type is data.service.type
      # existing service, broadcast to hosts connection
      service.addHost(data.private, publicInfo)
    else
      # check swarm connection to swarm only
      if data.service.type is "swarm"
        @service(data.service.name, data.service.type).addHost(data.private, publicInfo)
      else
        # non existing service, send error
        @send(publicInfo, "connect", 404, {
          message: "Service not found"
        })

  service: (name, type = "single") =>
    @services[name] = @services[name] || @createService(name, type)

    return @services[name]

  createListener: (port, host = "0.0.0.0") ->
    # listener factory
    return new Listener(port, host)

  createService: (name, type) =>
    # service factory
    return new Service(@listener, name, type)

  send: (host, request, status, data, done) ->
    # join status and request into the data block
    data.status = status || data.status
    data.request = request || data.request

    @listener.send(host, data, done)

  start: () ->
    @listener.listen()

# factory method
module.exports.create = (options) ->
  return new UDPHoleService(options)