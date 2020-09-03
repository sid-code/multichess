import games, moves, positions, layouts, moverules, playercolors
import options, sets, tables, random
from sugar import `=>`

type
  MCGameView* = ref object
    game*: MCGame
    playerColor*: Option[MCPlayerColor]
    layout*: MCLatticeLayout
    currentLegalMoves*: Table[MCPosition, seq[MCMove]]
    selectedPosition*: Option[MCPosition]

    ## If existent, a move that would capture a king.
    checks*: seq[MCMove]

    highlightedPositions: HashSet[MCPosition]
    possibleMovePositions: HashSet[MCPosition]

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

proc clearLegalMoves(cs: MCGameView) =
  cs.currentLegalMoves.clear()

proc calcLayout(cs: MCGameView) =
  cs.layout = layout(cs.game.rootNode)
  cs.layout.moveTopLeftTo((0, 0))

proc findCheck(cs: MCGameView) =
  cs.checks = cs.game.rootNode.checksInPosition()

proc calcMoves(cs: MCGameView) =
  cs.clearLegalMoves()
  for move in getAllLegalMoves(cs.game.rootNode):
    if cs.playerColor.isNone() or move.fromPos.getSquare().color == cs.playerColor.get():
      discard cs.currentLegalMoves.hasKeyOrPut(move.fromPos, @[])
      cs.currentLegalMoves[move.fromPos].add(move)

proc calcMovesAt(cs: MCGameView, p: MCPosition) =
  if p in cs.currentLegalMoves:
    return
  cs.currentLegalMoves[p] = @[]
  for move in getAllLegalMovesAt(cs.game.rootNode, p):
    if cs.playerColor.isNone() or move.fromPos.getSquare().color == cs.playerColor.get():
      cs.currentLegalMoves[p].add(move)

proc click*(cs: MCGameView, p: MCPosition) =
  cs.calcMovesAt(p)
  cs.clearSelection()
  for move in cs.currentLegalMoves[p]:
    cs.markPossibleMove(move.toPos)

proc update*(cs: MCGameView, game: MCGame) =
  cs.game = game
  cs.clearLegalMoves()
  cs.calcLayout()
  cs.findCheck()
  cs.clearSelection()

proc makeMove*(cs: MCGameView, move: MCMove) =
  discard cs.game.makeMove(move)
  cs.update(cs.game)
proc undoLastMove*(cs: MCGameView) =
  cs.game.undoLastMove()
  cs.update(cs.game)

proc newGameView*(game: MCGame, color = none[MCPlayerColor]()): MCGameView =
  result = MCGameView(
    playerColor: color,
    currentLegalMoves: initTable[MCPosition, seq[MCMove]](),
    selectedPosition: none[MCPosition](),
    highlightedPositions: initHashSet[MCPosition](),
    possibleMovePositions: initHashSet[MCPosition]())
  result.update(game)

proc makeRandomMove*(cs: MCGameView): MCMove =
  cs.calcMoves()
  var moves: seq[MCMove]
  for fp, ms in cs.currentLegalMoves:
    moves.add(ms)
  if len(moves) == 0:
    raise newException(ValueError, "cannot play random move; no legal moves.")
  result = sample(moves)
  cs.makeMove(result)
