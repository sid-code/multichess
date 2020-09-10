## Note: This module is for spawning barebones web workers. It is
## probably useless because no nim functions will be available for the
## worker. The real way to do this would be to have an entire module
## dedicated to the worker and spawn it with the generated JS
## file. I'm leaving this module in the source tree as reference
## material.

import dom

asm """
const toFuncStr = (func) => 'var framePtr={};(' + func.toString() + ')(this)';
const makeWorker = (funcStr) => new Worker(URL.createObjectURL(new Blob([funcStr])));
const initWorker = (func) => makeWorker(toFuncStr(func));
"""

type
  WebWorkerMessage* = object
    data: cstring
  WebWorker* {.importc.} = object
    onmessage*: proc(m: WebWorkerMessage)
  WebWorkerGlobalScope* = object
    discard

template webWorkerHeader() =
  # This is needed to avoid angering the JS runtime
  {.emit: "var framePtr = {};".}

proc initWorker*(prok: proc(ctx: WebWorkerGlobalScope)): WebWorker {.importc.}

proc postMessage*(ctx: WebWorkerGlobalScope; msg: cstring) {.importcpp: "#.postMessage(#)".}
proc setInterval*(w: WebWorkerGlobalScope, code: cstring, pause: int): ref Interval {.importcpp: "#.setInterval(#, #)".}
proc setInterval*(w: WebWorkerGlobalScope, function: proc (), pause: int): ref Interval {.importcpp: "#.setInterval(#, #)".}


when isMainModule:
  import dom
  import streams
  proc a(ctx: WebWorkerGlobalScope) =
    let a = newStringStream()
    ctx.postMessage("whee!")
  var wrk = initWorker(a)
  wrk.onmessage = proc(msg: WebWorkerMessage) =
    document.getElementById("result").innerText = msg.data
