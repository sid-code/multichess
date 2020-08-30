when not defined(js) and not defined(Nimdoc):
  {.error: "This module only works on the JavaScript platform".}

type
  PeerId* = cstring
  Peer* = ref PeerObj
  PeerObj {.importc.} = object of RootObj
  DataConnection* = ref DataConnectionObj
  DataConnectionObj {.importc.} = object of RootObj
    peer*: cstring
  PeerError* = object
    message*: cstring
    `type`*: cstring

proc newPeer*(): Peer {.importcpp: "new Peer()", nodecl.}
proc on*[T](p: Peer, event: cstring, fn: proc(v: T)) {.importcpp: "#.on(#, #)", nodecl.}
proc connect*(p: Peer, id: cstring): DataConnection {.importcpp: "#.connect(#)", nodecl.}
proc on*[T](p: DataConnection, event: cstring, fn: proc(v: T)) {.importcpp: "#.on(#, #)", nodecl.}
proc send*(p: DataConnection, data: cstring) {.importcpp: "#.send(#)", nodecl.}


when isMainModule:
  var p = newPeer()
  p.on("open", proc(id: cstring) =
                 echo id)
