import dom, asyncjs, jsffi

type
  FetchOptions* = object
    `method`*: cstring

  Headers* = object
    discard
  Request* = object
    discard
  Response* = object
    headers*: Headers
    ok*: bool
    status*: int
    statusText*: cstring
    `type`*: cstring
    url*: cstring
    useFinalURL*: bool

proc newHeaders*(): Headers {.importcpp: "new Headers()".}
proc append*(h: Headers, n, v: cstring) {.importcpp: "#.append(#, #)".}
proc delete*(h: Headers, n: cstring): cstring {.importcpp: "#.delete(#)".}
proc get*(h: Headers, n: cstring): cstring {.importcpp: "#.get(#)".}
proc entries(h: Headers): JsObject {.importcpp: "#.entries()".}
iterator items*(o: JsObject): JsObject =
  while true:
    let next = o.next()
    if to(next["done"], bool):
      break
    yield next["value"]
iterator items*(h: Headers): (cstring, cstring) =
  for pair in h.entries():
    yield (to(pair[0], cstring), to(pair[1], cstring))

proc fetch*(req: cstring | Request): Future[Response] {.importcpp: "fetch(#)".}
proc fetch*(req: cstring | Request, opts: FetchOptions): Future[Response]
    {.importcpp: "fetch(#, #)".}

# TODO: Finish these and factor this out?
proc text*(r: Response): Future[cstring] {.importcpp: "#.text()".}
