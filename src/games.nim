import latticenodes, boards, moves, moverules, positions, pieces, streams
import tables, json, strformat

type
  MCGame* = ref object
    numBoardFiles: int
    numBoardRanks: int
    startPosition: MCBoard
    nodeLookup: Table[MCLatticePos, MCLatticeNode[MCBoard]]
    rootNode*: MCLatticeNode[MCBoard]
    moveLog*: seq[MCMoveInfo]

proc newGame*(startPos: MCBoard): MCGame =
  new result
  result.startPosition = startPos
  result.numBoardRanks = startPos.numRanks
  result.numBoardFiles = startPos.numFiles
  result.moveLog = @[]
  result.nodeLookup = initTable[MCLatticePos, MCLatticeNode[MCBoard]]()

  result.rootNode = MCLatticeNode[MCBoard](board: startPos)

  result.nodeLookup[result.rootNode.latticePos] = result.rootNode

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
