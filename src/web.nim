include karax/prelude
import karax/vstyles
import options, tables, sets, random, streams, strformat, sequtils, base64
import dom, asyncjs
import html5_canvas
import peerjs
include multichess
import rpcs, clipboard, fetch
import piececlasses, boardeditor, gameview, movelog, serialization

# Constants

## Don't forget to change this if the css changes!
const squareSizePixels = 40


type
  LogEntry = tuple
    message: cstring
    color: cstring

  MCClientStatus = enum
    stConfig, stGame, stGameEnd
  MCClient = ref object
    view: Option[MCGameView]
    status: MCClientStatus
    boardEditor: MCBoardEditor
    master: bool
    id, peerid: PeerID
    pcolor: MCPlayerColor
    rpc: SimpleRPCPeer
    rpcInitialized: bool

  GameInitMessage = object
    opponentId: string
    spectator: bool
    board: MCBoard
    color: MCPlayerColor

  # Thrown if the peer rejects our move
  PeerRejectedMoveError = object of CatchableError

proc write*(s: Stream, im: GameInitMessage) =
  s.writeStrAndLen(im.opponentId)
  s.write(uint8(im.spectator))
  s.write(im.board)
  s.write(uint8(im.color))
proc read*(s: Stream, im: var GameInitMessage) =
  im.opponentId = s.readStrAndLen()
  im.spectator = bool(serialization.readUint8(s))
  s.read(im.board)
  im.color = MCPlayerColor(serialization.readUint8(s))

### Game client (including p2p stuff)
proc newMCClient(): MCClient =
  new result
  result.view = none[MCGameView]()
  result.status = stConfig
  result.master = false
  # dummy value, will be overwritten later
  result.rpc = initSimpleRPCPeer(proc(data: string) = discard)
  result.rpcInitialized = false
  result.id = nil
  result.peerid = nil
  result.pcolor = rand(mccWhite..mccBlack)

proc initGame(client: MCClient, spectator = false) {.async.} =
  # Pass in spectator = true if we are letting a spectator watch.
  if client.view.isNone():
    raise newException(ValueError, "cannot send game init without a game started")
  let view = client.view.get()
  client.pcolor = rand(mccWhite..mccBlack)
  view.setColor(client.pcolor)

  let initmsg = GameInitMessage(
    opponentId: $client.id,
    spectator: spectator,
    board: view.game.rootNode.board,
    color: oppositeColor(client.pcolor))

  let ss = newStringStream()
  ss.write(initmsg)
  let resp = await client.rpc.client.call("gameinit", ss.data)
  echo resp
  for info in view.game.moveLog:
    let ss = newStringStream()
    ss.write(info.move)
    let resp = await client.rpc.client.call("gamemove", ss.data)

proc initClientRpc(client: MCClient, conn: DataConnection) =
  if not client.rpcInitialized:
    client.rpc = initSimpleRPCPeer do (data: string):
      conn.send(cstring(base64.encode(data)))
    client.rpcInitialized = true

    conn.on("data") do (data: cstring):
      recv(client.rpc, base64.decode($data))

    client.rpc.server.register("gameinit") do (arg: string) -> string:
      if client.master:
        "no"
      else:
        var msg: GameInitMessage
        newStringStream(arg).read(msg)
        let pcolor = msg.color
        echo "GAMEINIT ", arg
        client.status = stGame
        client.view = some(newGameView(newGame(msg.board), color = some(pcolor)))
        redraw()
        "ok"

    client.rpc.server.register("gamemove") do (arg: string) -> string:
      echo "GAMEMOVE ", arg
      let view = client.view.get()

      var move: MCMove
      newStringStream(arg).read(view.game, move)
      view.makeMove(move)
      redraw()
      "ok"

proc makeAndSendMove(client: MCClient, move: MCMove) {.async.} =
  assert(client.view.isSome())
  let view = client.view.get()
  if client.peerid.isNil:
    view.makeMove(move)
  else:
    let ss = newStringStream()
    ss.write(move)
    let resp = await client.rpc.client.call("gamemove", ss.data)
    if resp == "ok":
      view.makeMove(move)
    else:
      raise newException(PeerRejectedMoveError, fmt"peer rejected move: {move}")
  redraw()

proc onConnectionOpen(client: MCClient, conn: DataConnection) {.async.} =
  client.peerid = conn.peer
  client.initClientRpc(conn)
  redraw()
  if not client.master:
    return
  if not client.view.isSome():
    return

proc onConnectionClose(client: MCClient, conn: DataConnection) =
  client.peerid = nil
  client.rpcInitialized = false
  echo "connection closed with ", conn.peer

proc registerConnection(client: MCClient, conn: DataConnection) {.async.} =
  echo "REGCON"

  conn.on("open") do (x: cstring):
    discard client.onConnectionOpen(conn)

  conn.on("close") do (x: cstring):
    client.onConnectionClose(conn)
  conn.on("disconnected") do (x: cstring):
    client.onConnectionClose(conn)

proc initPeer(client: MCClient, p: Peer, id: cstring) {.async.} =
  echo "INITPEER"
  client.id = id
  client.master = true
  redraw()
  p.on("connection") do (conn: DataConnection):
    if client.peerid.isNil:
      discard client.registerConnection(conn)

proc connectPeerTo(client: MCClient, p: Peer, id: cstring) {.async.} =
  client.master = false
  let conn = p.connect(id)
  await client.registerConnection(conn)

### Various Utility procs
proc dumpGameToClipboard(cl: MCClient) =
  cl.view.map do (v: MCGameView):
    let s = newStringStream()
    s.write(v.game)
    copyToClipboard(base64.encode(s.data))

proc getBoardContainerStyle(left: int, top: int): VStyle =
  style(
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring($left & "px")),
    (StyleAttr.top, cstring($top & "px")))

### URL LOADING
const corsProxy {.strdefine.} = "https://cors-anywhere.herokuapp.com"
proc getTextFromUrl(url: cstring): Future[string] {.async.} =
  let resp = await fetch(&(corsProxy & "/" & url))
  let txt = $await resp.text()
  return txt


proc showGameFromText(cl: MCClient, gt: string) {.async.} =
  let gameData = base64.decode(gt)
  let game = newStringStream($gameData).readGame()
  cl.status = stGame
  cl.view = some(newGameView(game))
  redraw()
  if cl.rpcInitialized:
    discard cl.initGame()

proc showGameFromUrl(cl: MCClient, url: cstring) {.async.} =
  let gameText = await getTextFromUrl(url)
  await cl.showGameFromText(gameText)

### Rendering

# Can't get karax to properly render SVG so I have to do this for now,
# don't worry about this code it's going to be replaced with much
# better SVG.
proc drawGameView(state: MCGameView, canvas: Canvas) =
  # size constants
  let f = state.game.rootNode.board.numFiles
  let r = state.game.rootNode.board.numRanks
  let w = float((f + 2) * squareSizePixels)
  let h = float((r + 2) * squareSizePixels)
  let dcx = f * squareSizePixels / 2
  let dcy = r * squareSizePixels / 2

  let (lw, lh) = state.layout.dims()

  let cc = document.querySelector(".client-container")
  canvas.width = lw * (f + 2) * squareSizePixels
  canvas.height = lh * (f + 2) * squareSizePixels
  let ctx = canvas.getContext2D()

  # Invert the table for sanity later, will have to look up a node's
  # position
  var placement = initTable[MCLatticeNode[MCBoard], MCLayoutPosition]()
  for np, node in state.layout.placement:
    placement[node] = np

  proc center(node: MCLatticeNode[MCBoard]): (float, float) {.closure.} =
    let np = placement[node]
    let (x, y) = (float(np[0]), float(np[1]))
    return (x * w + dcx, y * h + dcy)

  for node, np in placement:
    let (cx, cy) = center(node)

    for child in node.future:
      let (ccx, ccy) = center(child)
      ctx.strokeStyle = "blue"
      ctx.moveTo(cx, cy)
      ctx.lineTo(ccx, ccy)
      ctx.stroke()
    if not node.nextSibling.isNil:
      let (ccx, ccy) = center(node.nextSibling)
      ctx.strokeStyle = "green"
      ctx.moveTo(cx, cy)
      ctx.lineTo(ccx, ccy)
      ctx.stroke()

proc squareOnClick(cl: MCClient): proc(ev: Event, n: Vnode) =
  let state = cl.view.get()
  return proc(ev: Event, n: VNode) {.closure.} =
           # Note: using a closure for these parameters DOES NOT work
           # with karax (as of 2020 August 29). The event listeners
           # seem to be getting screwed up so we can't rely on passing
           # anything in by closure that isn't a constant.
           let target = ev.target
           if target.getAttribute("file").isNil: return
           let np = (parseInt(target.getAttribute("posx")),
                     parseInt(target.getAttribute("posy")))
           let file = parseInt(target.getAttribute("file"))
           let rank = parseInt(target.getAttribute("rank"))
           let node = state.layout.placement[np]
           let clickedPos = pos(node, file, rank)
           if state.isSelected(clickedPos):
             state.clearSelection()
           elif state.isPossibleMove(clickedPos):
             ## TODO: PROMOTION
             state.selectedPosition.map do (sp: MCPosition):
               let move = mv(sp, clickedPos, mcpNone)
               discard cl.makeAndSendMove(move)
           else:
             if clickedPos.hasPiece():
               state.click(clickedPos)
               state.selectPosition(clickedPos)

proc renderMadeWith(): VNode =
  result = buildHtml(tdiv):
    text "made with "
    a(href="https://nim-lang.org"):
      text "nim"
    text " using "
    a(href="https://peerjs.com/"):
      text "peerjs"
    text " to handle p2p connections."

proc renderConnectInput(): VNode =
  result = buildHtml(span):
    input(`type`="text", placeholder="opponent peer ID"):
      proc onkeydown(e: Event, n: VNode) =
        if KeyboardEvent(e).key == "Enter":
          window.location.hash = "#/c/" & e.target.value

proc renderConfigPanel(cl: MCClient): VNode =
  result = buildHtml(tdiv):
    if cl.id.isNil:
      text "waiting for peer id..."
    else:
      text "peer id: "
      text cl.id
    text " "
    if cl.peerid.isNil:
      renderConnectInput()
    else:
      text "connected to "
      text cl.peerid

    br()
    text "multichess!"
    br()
    text "load a game!  "
    input(`type`="text", placeholder="RAW paste url"):
      proc onkeydown(e: Event, n: VNode) =
        let val = $e.target.value
        if KeyboardEvent(e).key == "Enter":
          if val.startsWith("http"):
            window.location.hash = "#/g/" & e.target.value
          else:
            window.location.hash = "#/r/" & e.target.value
    br()
    text "start a game!"
    br()
    text "but first, a starting position"
    br()
    render(cl.boardEditor)
    if cl.view.isSome():
      br()
      text "ps: you have a game going currently!"
      br()
      button:
        text "return to game"
        proc onclick() =
          cl.status = stGame
    hr()
    renderMadeWith()

proc renderControls(client: MCClient): VNode =
  let state = client.view.get()
  result = buildHtml(tdiv):
    tdiv(class="client-controls"):
      button():
        text "I'm feeling lucky"
        proc onclick() =
          let move = state.getRandomMove()
          discard client.makeAndSendMove(move)

      if state.isSinglePlayer():
        button(onclick=proc() = state.undoLastMove()):
          text "oops"
      if len(state.checks) > 0:
        button(onclick=proc() = state.highlightCheckingPieces()):
          text "highlight checking pieces"
      button:
        # TODO: refactor this into a "flashing button" thing
        let origText = "copy game to clipboard"
        text origText
        proc onclick(e: Event, n: VNode) =
          client.dumpGameToClipboard()
          e.target.innerText = "copied!"
          discard window.setTimeout(
            proc() = e.target.innerText = origText,
            1000)

      button:
        proc onclick() =
          state.config.lazyLoadMoves = not state.config.lazyLoadMoves

        if state.config.lazyLoadMoves:
          text "eagerly load moves":
        else:
          text "lazy load moves"

      if len(state.getStatusText()) > 0:
        text " status: " & state.getStatusText()
    #tdiv(class="client-movelog"):
    #  renderMoveLog(state.game) do (i: MCMoveInfo):
    #    echo i

proc renderGame(client: MCClient): VNode =
  let state = client.view.get()
  var game = state.game

  # See comment on drawGameView... bleh. It even makes me have to do
  # this. Pray that your DOM renders in 10ms (or whatever's after the
  # proc argument)
  discard window.setTimeout(
    proc() =
      let cnv = document.getElementById("backdrop")
      if not cnv.isNil: state.drawGameView(cast[Canvas](cnv)),
    10)

  var actionableBoards: HashSet[MCLatticeNode[MCBoard]]
  for mpos, moves in state.currentLegalMoves:
    if len(moves) > 0:
      actionableBoards.incl(mpos.node)

  result = buildHtml(tdiv):
    renderControls(client)

    tdiv(class="client-container"):
      canvas(class="client-hints", id="backdrop")
      for np, node in state.layout.placement:
        let isActionable = node in actionableBoards
        let (x, y) = np
        let w = (node.board.numFiles + 2) * (squareSizePixels)
        let h = (node.board.numRanks + 2) * (squareSizePixels)

        tdiv(class="board-container", style=getBoardContainerStyle(x * w, y * h)):
          let onclick = squareOnClick(client)
          var boardClass = "board"
          if isActionable: boardClass &= " board-actionable"
          tdiv(class=boardClass, onclick=onclick):
            let board = node.board

            let ranks = if client.view.get().playerColor == some(mccBlack):
                          toSeq(countup(0, board.numRanks - 1))
                        else:
                          toSeq(countdown(board.numRanks - 1, 0))

            for r in ranks:
              for f in countup(0, board.numFiles - 1):
                let blackSquareClass = if (f + r) mod 2 == 0:
                                         kstring("square square-black")
                                       else:
                                         kstring("square square-white")

                let elPos = pos(node, f, r)
                tdiv(class=blackSquareClass):
                  tdiv(class=getClassFor(elPos.getSquare()),
                       file=kstring($f),
                       rank=kstring($r),
                       posx=kstring($x),
                       posy=kstring($y))

                  if state.isPossibleMove(elPos):
                      tdiv(class="highlight highlight-move")
                  if state.isSelected(elPos):
                      tdiv(class="highlight highlight-select")
                  if state.isChecked(elPos) or state.isHighlighted(elPos):
                      tdiv(class="highlight highlight-check")

              br()

proc render(cl: MCClient): VNode =
  result = buildHtml(tdiv):
    case cl.status:
      of stConfig:
        renderConfigPanel(cl)
      of stGame, stGameEnd:
        renderGame(cl)

proc randomString(length: int): string =
  for _ in 0 ..< length:
    result.add(char(rand(int('a') .. int('z'))))

proc main() {.async.} =
  # This will be used to connect to and communicate with another
  # instance of this program.
  let p = newPeer(
    id = randomString(12),
    host = cstring"doa.skulk.org",
    path = cstring"/myapp",
    port = 2301,
    secure = false,
  )

  let client = newMCClient()

  proc gotPeerId(id: cstring) =
    discard client.initPeer(p, id)

  # Set up the board editor and its callback. In the callback, we set
  # up the game and start it.
  client.boardEditor = newBoardEditor(mcStartPos5x5) do (b: MCBoard):
    client.status = stGame
    client.view = some(newGameView(newGame(b)))

    if client.rpcInitialized:
      discard client.initGame()

  # Register the most basic callbacks on the peer object
  p.on("open", gotPeerId)
  p.on("error") do (err: PeerError):
    if err.`type` == "peer-unavailable":
      discard #TODO
    else:
      raise newException(Exception, fmt"peer error: {err}")


  # Tell karax what to render
  proc renderClient(): VNode =
    render(client)

  setRenderer renderClient

  # Track location hash changes and update them properly
  # TODO: when hash goes from something -> empty, update accordingly.
  window.addEventListener("hashchange") do (ev: Event):
    if window.location.hash == "":
      client.status = stConfig
      redraw()
    elif window.location.hash.startsWith("#/g/"):
      discard client.showGameFromUrl(($window.location.hash)[4..^1])
      redraw()
    elif window.location.hash.startsWith("#/r/"):
      discard client.showGameFromText(($window.location.hash)[4..^1])
      redraw()
    elif window.location.hash.startsWith("#/c/"):
      discard client.connectPeerTo(p, ($window.location.hash)[4..^1])
      window.location.hash = ""

  window.dispatchEvent(newEvent("hashchange"))

when isMainModule:
  randomize()
  discard main()
