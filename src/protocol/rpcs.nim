import std/[strformat, tables, random, streams]
import serialization

when defined(js):
  import asyncjs
else:
  import asyncdispatch

type
  RPCMessage = object
    randnum: uint32
    request: bool # request (true) or response (false)?
    error: bool
    fn: string
    arg: string
  RPCProc = proc(arg: string): string
  SimpleRPCServer* = ref object
    fns: Table[string, RPCProc]

  SendProc = proc(data: string)

  ResolveCallback = proc(resp: string)
  SimpleRPCClient* = ref object
    resolveCallbacks: Table[uint32, ResolveCallback]
    send: SendProc

  SimpleRPCPeer* = object
    client*: SimpleRPCClient
    server*: SimpleRPCServer

when defined(js):
  proc write(stream: Stream, rm: RPCMessage) =
    stream.write(uint32(rm.randnum))
    stream.write(uint8(rm.request))
    stream.write(uint8(rm.error))
    stream.writeStrAndLen(rm.fn)
    stream.writeStrAndLen(rm.arg)

proc readRPCMessage(stream: Stream): RPCMessage =
  when defined(js):
    result.randnum = serialization.readUint32(stream)
    result.request = bool(serialization.readUint8(stream))
    result.error = bool(serialization.readUint8(stream))
    result.fn = stream.readStrAndLen()
    result.arg = stream.readStrAndLen()
  else:
    stream.read(result)

proc newSimpleRPCServer*(): SimpleRPCServer =
  new(result)
  result.fns = initTable[string, RPCProc]()

proc setSend*(c: SimpleRPCClient, send: SendProc) =
  c.send = send

proc newSimpleRPCClient*(send: SendProc): SimpleRPCClient =
  new(result)
  result.resolveCallbacks = initTable[uint32, ResolveCallback]()
  result.setSend(send)

proc initSimpleRPCPeer*(send: SendProc): SimpleRPCPeer =
  result.server = newSimpleRPCServer()
  result.client = newSimpleRPCClient(send)

proc call*(s: SimpleRPCServer, fn: string, arg: string): RPCMessage =
  if fn notin s.fns:
    raise newException(KeyError, fmt"rpc server does not support function {fn}")
  result.request = false
  result.error = false
  result.fn = fn
  try:
    result.arg = s.fns[fn](arg)
  except:
    result.arg = getCurrentExceptionMsg()
    result.error = true
      

proc call*(s: SimpleRPCServer, msg: RPCMessage): RPCMessage =
  result = s.call(msg.fn, msg.arg)
  result.randnum = msg.randnum

proc register*(s: SimpleRPCServer, fn: string, prok: RPCProc) =
  if fn in s.fns:
    raise newException(KeyError, fmt"rpc function `{fn}` already defined.")
  s.fns[fn] = prok
  
proc recv*(c: SimpleRPCClient, msg: RPCMessage) =
  if msg.request:
    # Discarding requests
    return

  if msg.randnum in c.resolveCallbacks:
    c.resolveCallbacks[msg.randnum](msg.arg)
    c.resolveCallbacks.del(msg.randnum)
    return
  else:
    echo fmt"dropped message {msg}"
  
proc recv*(peer: var SimpleRPCPeer, data: string) =
  let msg = readRPCMessage(newStringStream(data))
  if msg.request:
    let ss = newStringStream()
    let resp = peer.server.call(msg)
    ss.write(resp)
    peer.client.send(ss.data)
  else:
    peer.client.recv(msg)

proc call*(c: SimpleRPCClient, fn: string, arg: string): Future[string] =
  let randnum = uint32(rand(high(int32))) # rand doesn't support high(uint32)
  result = newPromise() do (resolve: proc(resp: string)):
    c.resolveCallbacks[randnum] = resolve
  let msg = RPCMessage(request: true,
                       error: false,
                       randnum: randnum,
                       fn: fn, arg: arg)
  var ss = newStringStream()
  ss.write(msg)
  c.send(ss.data)

when isMainModule:
  let msg = RPCMessage(request: true,
                       error: false,
                       randnum: 10101,
                       fn: "gameinit", arg: "wowowowo")
  var s = newStringStream()
  s.write(msg)
  s.setPosition(0)
  echo s.readRPCMessage()
