import strformat, tables, json, random

when defined(js):
  import asyncjs
else:
  import asyncdispatch

type
  RPCMessage = object
    randnum: int
    request: bool # request (true) or response (false)?
    error: bool
    fn: string
    arg: JsonNode
  RPCProc = proc(arg: JsonNode): JsonNode
  SimpleRPCServer* = object
    fns: Table[string, RPCProc]

  SendProc = proc(data: cstring)
  RPCCallback* = proc(res: JsonNode)
  RPCCallbackSet* = object
    success*: RPCCallback
    failure*: RPCCallback

  ResolveCallback = proc(resp: JsonNode)
  SimpleRPCClient* = object
    resolveCallbacks: Table[int, ResolveCallback]
    send: SendProc

  SimpleRPCPeer* = object
    client*: SimpleRPCClient
    server*: SimpleRPCServer

proc initSimpleRPCServer*(): SimpleRPCServer =
  result.fns = initTable[string, RPCProc]()

proc setSend*(c: var SimpleRPCClient, send: SendProc) =
  c.send = send

proc initSimpleRPCClient*(send: SendProc): SimpleRPCClient =
  result.resolveCallbacks = initTable[int, ResolveCallback]()
  result.setSend(send)

proc initSimpleRPCPeer*(send: SendProc): SimpleRPCPeer =
  result.server = initSimpleRPCServer()
  result.client = initSimpleRPCClient(send)

proc call*(s: SimpleRPCServer, fn: string, arg: JsonNode): RPCMessage =
  if fn notin s.fns:
    raise newException(KeyError, fmt"rpc server does not support function {fn}")
  result.request = false
  result.error = false
  result.fn = fn
  try:
    result.arg = s.fns[fn](arg)
  except:
    result.arg = %(getCurrentExceptionMsg())
    result.error = true
      

proc call*(s: SimpleRPCServer, msg: RPCMessage): RPCMessage =
  result = s.call(msg.fn, msg.arg)
  result.randnum = msg.randnum

proc register*(s: var SimpleRPCServer, fn: string, prok: RPCProc) =
  if fn in s.fns:
    raise newException(KeyError, fmt"rpc server does not support redefining functions")
  s.fns[fn] = prok
  
proc recv*(c: var SimpleRPCClient, msg: RPCMessage) =
  if msg.request:
    # Discarding requests
    return

  if msg.randnum in c.resolveCallbacks:
    c.resolveCallbacks[msg.randnum](msg.arg)
    c.resolveCallbacks.del(msg.randnum)
    return
  else:
    echo fmt"dropped message {msg}"
  
proc recv*(peer: var SimpleRPCPeer, data: cstring) =
  let msg = to(parseJson($data), RPCMessage)
  if msg.request:
    peer.client.send(cstring($(%*peer.server.call(msg))))
  else:
    peer.client.recv(msg)

proc call*(c: var SimpleRPCClient, fn: string, arg: JsonNode): Future[JsonNode] =
  let randnum = rand(high(int))
  result = newPromise() do (resolve: proc(resp: JsonNode)):
    c.resolveCallbacks[randnum] = resolve
  let msg = RPCMessage(request: true,
                       randnum: randnum,
                       fn: fn, arg: arg)
  let msgStr = $(%* msg)
  c.send(msgStr)
