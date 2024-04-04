import games, boards, moves, positions, layouts, moverules, playercolors, latticenodes
import options, sets, tables, random, strformat
from sugar import `=>`

type
  MCMoveCallback* = proc(m: MCMove)
  MCGameViewConfig = object
    lazyLoadMoves*: bool
    moveCallback*: MCMoveCallback

  MCGameView* = ref object
    config*: MCGameViewConfig
    game*: MCGame
    playerColor*: Option[MCPlayerColor]
    layout*: MCLatticeLayout
    currentLegalMoves*: Table[MCPosition, seq[MCMove]]
    selectedPosition*: Option[MCPosition]

    premoves: Table[MCPosition, MCMove]

    ## If existent, a move that would capture a king.
    checks*: seq[MCMove]

    ## Tells the client what's going on, like "white is in checkmate"
    statusText*: string

    possibleMoveHighlightClass*: cstring
    highlightedPositions: HashSet[MCPosition]
    possibleMovePositions: HashSet[MCPosition]

const moveHighlightClass = cstring"highlight-move"
const premoveHighlightClass = cstring"highlight-premove"

proc initGameViewConfig*(lazyLoadMoves = false,
                         moveCallback: MCMoveCallback = nil): MCGameViewConfig =
  result.lazyLoadMoves = lazyLoadMoves
  result.moveCallback = moveCallback

proc update*(cs: MCGameView, game: MCGame)
proc newGameView*(game: MCGame, config = initGameViewConfig(), color = none[MCPlayerColor]()): MCGameView =
  result = MCGameView(
    config: config,
    playerColor: color,
    currentLegalMoves: initTable[MCPosition, seq[MCMove]](),
    premoves: initTable[MCPosition, MCMove](),
    selectedPosition: none[MCPosition](),
    highlightedPositions: initHashSet[MCPosition](),
    possibleMovePositions: initHashSet[MCPosition]())
  result.update(game)

proc clearSelection*(cs: MCGameView) =
  cs.selectedPosition = none[MCPosition]()
  init(cs.possibleMovePositions)
  init(cs.highlightedPositions)

proc isSelected*(cs: MCGameView, pos: MCPosition): bool =
  let res = cs.selectedPosition.map(p => p == pos)
  if res.isSome():
    return res.get()
  else:
    return false

proc isPossibleMove*(cs: MCGameView, pos: MCPosition): bool =
  return pos in cs.possibleMovePositions
proc isPossibleNormalMove*(cs: MCGameView, pos: MCPosition): bool =
  return cs.possibleMoveHighlightClass == moveHighlightClass and
         cs.isPossibleMove(pos)
proc isPossiblePremove*(cs: MCGameView, pos: MCPosition): bool =
  return cs.possibleMoveHighlightClass == premoveHighlightClass and
         cs.isPossibleMove(pos)

proc isHighlighted*(cs: MCGameView, pos: MCPosition): bool =
  return pos in cs.highlightedPositions

proc isChecked*(cs: MCGameView, pos: MCPosition): bool =
  for check in cs.checks:
    if check.toPos == pos:
      return true
  return false

proc selectPosition*(cs: MCGameView, pos: MCPosition) =
  cs.selectedPosition = some(pos)
proc markPossibleMove*(cs: MCGameView, pos: MCPosition) =
  cs.possibleMovePositions.incl(pos)

proc highlightPosition*(cs: MCGameView, pos: MCPosition) =
  cs.highlightedPositions.incl(pos)

proc highlightCheckingPieces*(cs: MCGameView) =
  cs.clearSelection()
  for check in cs.checks:
    cs.highlightPosition(check.fromPos)

proc isSinglePlayer*(cs: MCGameView): bool =
  cs.playerColor.isNone()
proc setSinglePlayer*(cs: MCGameView) =
  cs.playerColor = none[MCPlayerColor]()
proc setColor*(cs: MCGameView, color: MCPlayerColor) =
  cs.playerColor = some(color)


proc makeMove*(cs: MCGameView, move: MCMove, noCallback = false) =
  discard cs.game.makeMove(move)

  if not noCallback:
    if cs.config.moveCallback.isNil:
      raise newException(ValueError, "missing move callback")
    cs.config.moveCallback(move)

  cs.update(cs.game)

proc makePremove*(cs: MCGameView, premove: MCMove) =
  # Does not call update because the game state doesn't actually
  # change
  cs.clearSelection()
  cs.premoves[premove.fromPos] = premove

proc removePremove*(cs: MCGameView, premovePos: MCPosition) =
  cs.clearSelection()
  cs.premoves.del(premovePos)

proc removePremove*(cs: MCGameView, premove: MCMove) =
  cs.clearSelection()
  cs.premoves.del(premove.fromPos)

proc getPremoves*(cs: MCGameView): Table[MCPosition, MCMove] =
  cs.premoves

proc undoLastMove*(cs: MCGameView) =
  cs.game.undoLastMove()
  cs.update(cs.game)

proc clearPremoves*(cs: MCGameView) =
  cs.premoves.clear()

proc clearLegalMoves(cs: MCGameView) =
  cs.currentLegalMoves.clear()

proc calcLayout(cs: MCGameView) =
  cs.layout = layout(cs.game.rootNode)
  if cs.playerColor == some(mccBlack):
    cs.layout.scale((1, -1))
  cs.layout.moveTopLeftTo((0, 0))

proc findCheck(cs: MCGameView) =
  cs.checks = cs.game.rootNode.getAllChecksInPosition()

proc updateStatusText(cs: MCGameView) =
  if len(cs.currentLegalMoves) == 0:
    var toPlay = mccWhite
    for n in cs.game.rootNode.getNodesNeedingMove():
      toPlay = n.board.toPlay
      break

    if len(cs.checks) > 0:
      cs.statusText = fmt"{toPlay} is in checkmate."

proc getStatusText*(cs: MCGameView): cstring =
  return cs.statusText

proc calcMoves(cs: MCGameView) =
  cs.clearLegalMoves()
  for move in getAllLegalMoves(cs.game.rootNode):
    if cs.playerColor.isNone() or move.fromPos.getSquare().color == cs.playerColor.get():
      discard cs.currentLegalMoves.hasKeyOrPut(move.fromPos, @[])
      cs.currentLegalMoves[move.fromPos].add(move)
  cs.updateStatusText()

proc calcMovesAt(cs: MCGameView, p: MCPosition) =
  if p in cs.currentLegalMoves:
    return
  cs.currentLegalMoves[p] = @[]
  for move in getAllLegalMovesAt(cs.game.rootNode, p):
    if cs.isSinglePlayer() or move.fromPos.getSquare().color == cs.playerColor.get():
      cs.currentLegalMoves[p].add(move)

proc markPremoves(cs: MCGameView, p: MCPosition) =
  cs.possibleMoveHighlightClass = premoveHighlightClass
  let toPlayColor = p.node.board.toPlay
  let isPremoveBoardActive = some(toPlayColor) == cs.playerColor
    
  var premoveBoard = initBlankBoard(
    numFiles = p.node.board.numFiles,
    numRanks = p.node.board.numRanks,
    toPlay = oppositeColor(toPlayColor))
    
  premoveBoard[p.file, p.rank] = p.getSquare()

  let preferredSiblingDirection =
    if toPlayColor == mccWhite:
      mclsPrev
    else:
      mclsNext

  # for this, we need to fake a new node and calculate the moves
  # from that node, then transplant them back to this node. That's
  # why the latticenodes module has a withTempBranch proc.

  if isPremoveBoardActive:
    for move in p.getPseudoLegalMoves(premove = true):
      cs.markPossibleMove(move.toPos)
  else:
    p.node.withTempBranch(
      premoveBoard,
      preferredSiblingDirection) do (temp: MCLatticeNode[MCBoard]):
        let premovePos = pos(temp, p.file, p.rank)
        for move in premovePos.getPseudoLegalMoves(premove = true):
          let movedToTempNode = move.toPos.node == temp
          let realToPos =
            if movedToTempNode:
              move.toPos.onNode(p.node)
            else:
              move.toPos
          cs.markPossibleMove(realToPos)

proc click*(cs: MCGameView, p: MCPosition, rightClick = false) =
  cs.clearSelection()
  cs.selectPosition(p)

  let toPlayColor = p.node.board.toPlay
  let pieceColor = p.getSquare().color
  if not rightclick and (cs.isSinglePlayer() or some(toPlayColor) == cs.playerColor):
    # not a premove
    cs.possibleMoveHighlightClass = moveHighlightClass
    cs.calcMovesAt(p)
    for move in cs.currentLegalMoves[p]:
      cs.markPossibleMove(move.toPos)
  elif some(pieceColor) == cs.playerColor:
    # premove
    cs.markPremoves(p)

proc processPremoves(cs: MCGameView): bool =
  ## Checks for and plays any premoves that need to be played. If a
  ## premove got played, this proc will return `true`, otherwise
  ## `false`. This is used by the `update` to avoid duplicating work.
  ##
  ## A premove will be played if all of the following are true:
  ##   - The board it was made on has received a move.
  ##   - Said move caused a check
  ##   - The premove resolves said check.
  ##      - If the premove does not resolve said check,
  ##      - it will be ignored and deleted. This is in contrast
  ##        with standard premove features.
  ##
  ## This should ONLY be called after the game view knows about the
  ## current checks in the position. Otherwise it will always do
  ## nothing.
  if cs.game.getMoveCount() == 0 or len(cs.checks) == 0:
    echo "position does not qualify for premoves"
    return false

  var chosenPremove: Option[MCMove]
  let lastMoveInfo = cs.game.getLastMoveInfo().get()
  let whoMoved = lastMoveInfo.move.fromPos.getSquare().color
  let nf = lastMoveInfo.move.fromPos.node
  let nt = lastMoveInfo.move.toPos.node
  for _, premove in cs.premoves.pairs:
    var premoveFromNode = premove.fromPos.node
    var premoveToNode = premove.toPos.node
    # We need to "transplant" the premove to the new node.

    if not lastMoveInfo.newFromNode.isNil and
       lastMoveInfo.newFromNode.past == premoveFromNode:
      premoveFromNode = lastMoveInfo.newFromNode
    elif lastMoveInfo.realToNode.past == premoveFromNode:
      premoveFromNode = lastMoveInfo.realToNode

    if not lastMoveInfo.newFromNode.isNil and
       lastMoveInfo.newFromNode.past == premoveToNode:
      premoveToNode = lastMoveInfo.newFromNode
    elif lastMoveInfo.realToNode.past == premoveToNode:
      premoveToNode = lastMoveInfo.realToNode

    let transplantedMove = mv(
      premove.fromPos.onNode(premoveFromNode),
      premove.toPos.onNode(premoveToNode),
      premove.promotion)

    if cs.game.rootNode.isMoveLegal(transplantedMove):
      # Since this move is legal, it resolves the check.
      # We have our move!
      echo "premove triggered", transplantedMove
      cs.makeMove(transplantedMove)
      chosenPremove = some(premove)
      break

  return chosenPremove.isSome()

proc update*(cs: MCGameView, game: MCGame) =
  # Note: status text is updated in calcMoves. This is because we only
  # want to actually update the status text when we are sure all legal
  # moves have been loaded.
  cs.game = game
  cs.clearLegalMoves()
  cs.calcLayout()
  cs.findCheck()
  cs.clearSelection()
  cs.statusText = ""
  if cs.processPremoves():
    # This means processPremoves made a move-- update will have been
    # called already on the new position.
    return
  if not cs.config.lazyLoadMoves:
    cs.calcMoves()

proc getRandomMove*(cs: MCGameView): MCMove =
  cs.calcMoves()
  var moves: seq[MCMove]
  for fp, ms in cs.currentLegalMoves:
    moves.add(ms)
  if len(moves) == 0:
    raise newException(ValueError, "cannot get random move; no legal moves.")
  result = sample(moves)
