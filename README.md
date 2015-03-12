# udpp2p
UDP hole punching service

## Installation:
```bash
npm install udpp2p
```

## Usage:

First, start up server that will try to establish connections between clients:
```coffee
server = require("udpp2p").createServer({
  port: 1338 # listen on port 1338
})

server.start() # lift server
```

After that, there are two types of topologies between udp clients.

### Centric topology
```
               ________ client1
              /
mainClient(host) ------ client2
              \________ client3
```

While using this type of service, you will need "host" client. everyone will then be connected right to him.
```coffee
client = require("udpp2p").createClient({
  port: 1338
  host: "127.0.0.1"
  service: {
    name: "Service"
    type: "single" # when using swarm, use "swarm" instead of single
    host: true
  }
})

client.on "fail", (request, status, message) ->
  console.log "Request[#{request}] failed with status[#{status}] and message[#{message}]"

client.on "connect", (publicInfo) ->
  console.log "Client connected #{publicInfo.address}:#{publicInfo.port}"

client.on "data", (publicInfo, data) ->
  console.dir data

client.start()
```

Since host is not enough and you can't have more hosts centric topology, you will need clients:
```coffee
client = require("../udpp2p").createClient({
  port: 1338
  host: "127.0.0.1"
  service: {
    name: "Service"
    type: "single"
  }
})

# use same callbacks as in host

client.start()
```

### Swarm topology ( everyone to everyone )

In this topology, every client is connected to every client. Because of that, all you need is clients.

```
client1 ------ client2
    \           /
     \         /
       client3
```

Example client:
```coffee
client = require("../udpp2p").createClient({
  port: 1338
  host: "127.0.0.1"
  service: {
    name: "Service"
    type: "swarm" # notice the swarm type of service
  }
})

# use same callbacks as in host

client.start()
```
