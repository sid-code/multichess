import games, latticenodes, moves, positions, layouts, moverules, playercolors
import options, sets, sequtils
from sugar import `=>`

type
  MCGameView* = ref object
    game*: MCGame
    playerColor*: Option[MCPlayerColor]
    layout*: MCLatticeLayout
    currentLegalMoves*: seq[MCMove]
    selectedPosition*: Option[MCPosition]

    ## If existent, a move that would capture a king.
    checks*: seq[MCMove] 

    highlightedPositions*: HashSet[MCPosition]

proc isSelected*(cs: MCGameView, pos: MCPosition): bool =
  let res = cs.selectedPosition.map(p => p == pos)
  if res.isSome():
    return res.get()
  else:
    return false

proc isHighlighted*(cs: MCGameView, pos: MCPosition): bool =
  return pos in cs.highlightedPositions

proc isChecked*(cs: MCGameView, pos: MCPosition): bool =
  for check in cs.checks:
    if check.toPos == pos:
      return true
  return false

proc isSinglePlayer*(cs: MCGameView): bool =
  cs.playerColor.isNone()

proc clearSelection*(cs: MCGameView) =
  cs.selectedPosition = none[MCPosition]()
  init(cs.highlightedPositions)
  

proc calcLayout(cs: MCGameView) =
  cs.layout = layout(cs.game.rootNode)
  cs.layout.moveTopLeftTo((0, 0))

proc findCheck(cs: MCGameView) =
  cs.checks = cs.game.rootNode.checksInPosition()

proc calcMoves(cs: MCGameView) =
  if cs.playerColor.isSome():
    cs.currentLegalMoves = @[]
    for move in getAllLegalMoves(cs.game.rootNode):
      if move.fromPos.getSquare().color == cs.playerColor.get():
        cs.currentLegalMoves.add(move)
  else:
    cs.currentLegalMoves = toSeq(getAllLegalMoves(cs.game.rootNode))

proc update*(cs: MCGameView, game: MCGame) =
  cs.game = game
  cs.calcLayout()
  cs.findCheck()
  cs.calcMoves()
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
