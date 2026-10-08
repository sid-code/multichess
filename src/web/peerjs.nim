when not defined(js) and not defined(Nimdoc):
  {.error: "This module only works on the JavaScript platform".}

type
  PeerId* = cstring
  Peer* = ref PeerObj
  PeerObj {.importc.} = object of RootObj
    id*: PeerId
  DataConnection* = ref DataConnectionObj
  DataConnectionObj {.importc.} = object of RootObj
    peer*: cstring
  PeerError* = object
    message*: cstring
    `type`*: cstring

proc newPeer*(id: cstring = nil,
              host = cstring"0.peerjs.com",
              path = cstring"/",
              port = 443,
              pingInterval = 5000,
              secure = true,
              debug = 0): Peer {.importcpp: """new Peer(#, {
  host: #,
  path: #,
  port: #,
  pingInterval: #,
  secure: #,
  debug: #,
})
""".}

proc on*[T](p: Peer, event: cstring, fn: proc(v: T)) {.importcpp: "#.on(#, #)", nodecl.}
proc connect*(p: Peer, id: cstring): DataConnection {.importcpp: "#.connect(#)", nodecl.}
proc on*[T](p: DataConnection, event: cstring, fn: proc(v: T)) {.importcpp: "#.on(#, #)", nodecl.}
proc send*(p: DataConnection, data: cstring) {.importcpp: "#.send(#)", nodecl.}


when isMainModule:
  var p = newPeer()
  p.on("open", proc(id: cstring) =
                 echo id)
