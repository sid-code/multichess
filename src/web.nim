include karax/prelude
import karax/vstyles
import options, tables, sets, json, random, streams, strformat, sequtils
import dom, asyncjs
import html5_canvas
import peerjs
include multichess
import rpcs, clipboard, fetch
import piececlasses, boardeditor, gameview, movelog

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
    board: MCBoard
    color: MCPlayerColor

  # Thrown if the peer rejects our move
  PeerRejectedMoveError = object of CatchableError

### Game client (including p2p stuff)
proc newMCClient(): MCClient =
  new result
  result.view = none[MCGameView]()
  result.status = stConfig
  result.master = false
  # dummy value, will be overwritten later
  result.rpc = initSimpleRPCPeer(proc(data: cstring) = discard)
  result.rpcInitialized = false
  result.id = nil
  result.peerid = nil
  result.pcolor = rand(mccWhite..mccBlack)

proc initGame(client: MCClient, spectator = false): JsonNode {.async.} =
  # Pass in spectator = true if we are letting a spectator watch.
  if client.view.isNone():
    raise newException(ValueError, "cannot send game init without a game started")
  let view = client.view.get()
  client.pcolor = rand(mccWhite..mccBlack)
  view.setColor(client.pcolor)

  let gameInitMessage = GameInitMessage(
    opponentId: $client.id,
    board: view.game.rootNode.board,
    color: oppositeColor(client.pcolor))

  let resp = await client.rpc.client.call("gameinit", %* gameInitMessage)
  echo resp
  for info in view.game.moveLog:
    let resp = await client.rpc.client.call("gamemove", %* info.move)

proc initClientRpc(client: MCClient, conn: DataConnection) =
  if not client.rpcInitialized:
    client.rpc = initSimpleRPCPeer(proc(data: cstring) = conn.send(data))
    client.rpcInitialized = true
    client.rpc.server.register("gameinit") do (arg: JsonNode) -> JsonNode:
      if client.master:
        %*"no"
      else:
        let msg = to(arg, GameInitMessage)
        let pcolor = msg.color
        echo "GAMEINIT ", arg
        client.status = stGame
        client.view = some(newGameView(newGame(msg.board), color = some(pcolor)))
        redraw()
        %*"ok"

    client.rpc.server.register("gamemove") do (arg: JsonNode) -> JsonNode:
      echo "GAMEMOVE ", arg
      let view = client.view.get()
      let move = view.game.toMove(arg)
      view.makeMove(move)
      redraw()
      %*"ok"

proc makeAndSendMove(client: MCClient, move: MCMove) {.async.} =
  assert(client.view.isSome())
  let view = client.view.get()
  let resp = await client.rpc.client.call("gamemove", %* move)
  if resp != %* "ok":
    raise newException(PeerRejectedMoveError, fmt"peer rejected move: {move}")
  view.makeMove(move)
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
  conn.on("data", proc(data: cstring) = recv(client.rpc, data))

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
    copyToClipboard(s.data)

proc getBoardContainerStyle(left: int, top: int): VStyle =
  style(
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring($left & "px")),
    (StyleAttr.top, cstring($top & "px")))

### URL LOADING
const corsProxy {.strdefine.} = "https://cors-anywhere.herokuapp.com"
proc loadGameFromUrl(url: cstring): Future[MCGame] {.async.} =
  let res = await fetch(&(corsProxy & "/" & url))
  let gameText = await res.text()
  return newStringStream($gameText).readGame()

proc showGameFromUrl(cl: MCClient, url: cstring) {.async.} =
  let game = await loadGameFromUrl(url)
  cl.status = stGame
  cl.view = some(newGameView(game))
  redraw()
  if cl.rpcInitialized:
    discard cl.initGame()

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
    tdiv(class="client-movelog"):
      renderMoveLog(state.game) do (i: MCMoveInfo):
        echo i

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

proc renderMadeWith(): VNode =
  result = buildHtml(tdiv):
    text "made with "
    a(href="https://nim-lang.org"):
      text "nim"
    text " using "
    a(href="https://peerjs.com/"):
      text "peerjs"
    text " to handle p2p connections."

proc render(cl: MCClient): VNode =
  result = buildHtml(tdiv):
    case cl.status:
      of stConfig:
        if not cl.id.isNil:
          text "peer id: "
          text cl.id
        if cl.peerid.isNil:
          text " not connected."
        else:
          text " connected to "
          text cl.peerid

        br()
        text "multichess!"
        br()
        text "load a game!  "
        input(`type`="text", placeholder="RAW paste url"):
          proc onkeydown(e: Event, n: VNode) =
            if KeyboardEvent(e).key == "Enter":
              window.location.hash = "#/g/" & e.target.value

        br()
        text "start a game!"
        br()
        text "but first, a starting position"
        br()
        render(cl.boardEditor)
        hr()
        renderMadeWith()
      of stGame, stGameEnd:
        renderGame(cl)

proc main() {.async.} =
  # This will be used to connect to and communicate with another
  # instance of this program.
  let p = newPeer()

  let client = newMCClient()

  # Set up the board editor and its callback. In the callback, we set
  # up the game and start it.
  client.boardEditor = newBoardEditor(mcStartPos5x5) do (b: MCBoard):
    client.status = stGame
    client.view = some(newGameView(newGame(b)))

    if client.rpcInitialized:
      discard client.initGame()

  # Register the most basic callbacks on the peer object
  p.on("open", proc(id: cstring) =
                 discard client.initPeer(p, id)
                 redraw())

  p.on("error", proc(err: PeerError) =
                  if err.`type` == "peer-unavailable":
                    discard #TODO
                  else:
                    raise newException(Exception, "peer error: {%err}"))


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
    elif window.location.hash.startsWith("#/c/"):
      discard client.connectPeerTo(p, ($window.location.hash)[4..^1])
      window.location.hash = ""

  window.dispatchEvent(newEvent("hashchange"))

when isMainModule:
  randomize()
  discard main()
