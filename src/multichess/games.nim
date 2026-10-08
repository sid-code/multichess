import multichess/[latticenodes, boards, moves, moverules]
import std/[tables, strformat, options]

type
  ## Configuration options for a game
  MCGameConfig* = object
    ## The game's initial board (root node) starting position.
    startPosition: MCBoard
    ## Do we allow the player to leave checks unresolved as long aas
    ## they want? If not, any check MUST be resolved on the next move.
    allowLongChecks: bool

  MCGame* = ref object
    config: MCGameConfig
    nodeLookup: Table[MCLatticePos, MCLatticeNode[MCBoard]]
    rootNode*: MCLatticeNode[MCBoard]
    moveLog: seq[MCMoveInfo]

proc initGameConfig*(startPosition: MCBoard,
                     allowLongChecks = false ): MCGameConfig =
  result.allowLongChecks = allowLongChecks
  result.startPosition = startPosition

proc newGame*(config: MCGameConfig): MCGame =
  new result
  result.config = config
  result.moveLog = @[]
  result.nodeLookup = initTable[MCLatticePos, MCLatticeNode[MCBoard]]()
  result.rootNode = newLatticeNode[MCBoard](board = result.config.startPosition)
  result.nodeLookup[result.rootNode.latticePos] = result.rootNode

proc newGame*(startPos: MCBoard): MCGame =
  let config = initGameConfig(startPosition = startPos)
  return newGame(config)
  
proc getStartPosition*(g: MCGame): MCBoard = g.config.startPosition
proc getMoveCount*(g: MCGame): int = len(g.moveLog)
proc getMoveLog*(g: MCGame): seq[MCMoveInfo] = g.moveLog
proc getLastMoveInfo*(g: MCGame): Option[MCMoveInfo] =
  if g.getMoveCount() > 0:
    return some(g.getMoveLog()[^1])
    

proc makeMove*(g: MCGame, move: MCMove): MCLatticeNode[MCBoard] =
  let moveInfo = move.makeMove()
  var newNodes: seq[MCLatticeNode[MCBoard]]
  newNodes.add(moveInfo.realToNode)
  if not moveInfo.newFromNode.isNil:
     newNodes.add(moveInfo.newFromNode)

  for node in newNodes:
    g.nodeLookup[node.latticePos] = node

  g.moveLog.add(moveInfo)
  return moveInfo.realToNode

proc undoLastMove*(g: MCGame) =
  if len(g.moveLog) == 0:
    return

  let lastMoveInfo = g.moveLog.pop()
  lastMoveInfo.undoMove()

proc getByLatticePos*(g: MCGame, pos: MCLatticePos): MCLatticeNode[MCBoard] =
  g.nodeLookup.getOrDefault(pos, nil)
