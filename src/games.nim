import latticenodes, boards, moves, moverules, positions, pieces
import tables, json, strformat

type
  MCGame* = object
    numBoardFiles: int
    numBoardRanks: int
    startPosition: MCBoard
    nodeLookup: Table[seq[int], MCLatticeNode[MCBoard]]
    rootNode*: MCLatticeNode[MCBoard]
    moveLog*: seq[MCMoveInfo]

proc initGame*(startPos: MCBoard): MCGame =
  result.startPosition = startPos
  result.numBoardRanks = startPos.numRanks
  result.numBoardFiles = startPos.numFiles
  result.moveLog = @[]
  result.nodeLookup = initTable[seq[int], MCLatticeNode[MCBoard]]()

  result.rootNode = MCLatticeNode[MCBoard](
    board: startPos,
    latticePos: @[],
    nextSibling: nil, prevSibling: nil,
    past: nil,
    future: @[])

  result.nodeLookup[result.rootNode.latticePos] = result.rootNode

proc makeMove*(g: var MCGame, move: MCMove): MCLatticeNode[MCBoard] =
  let newNodes = move.makeMove()

  for node in newNodes:
    g.nodeLookup[node.latticePos] = node

  let newToNode = newNodes[0] # This is a convention
  let newFromNode = if len(newNodes) == 1:
                      nil
                    else:
                      newNodes[1]

  g.moveLog.add(MCMoveInfo(move: move,
                           realToNode: newToNode,
                           newFromNode: newFromNode))
  return newToNode


# It may seem strange to delegate the gory details of making moves to
# some other makeMove function but then go ahead and undo moves with
# this function. The fact is, undoing a move requires a bit more
# information than the move itself contains.
proc undoLastMove*(g: var MCGame) =
  if len(g.moveLog) == 0:
    return

  let lastMoveInfo = g.moveLog.pop()
  let lastMove = lastMoveInfo.move
  let realToNode = lastMoveInfo.realToNode
  # For normal moves, this should be all there is to do
  realToNode.unlinkLeaf()
  if lastMove.isTimeJump():
    # This is where the piece moved
    let moved = realToNode.board[lastMove.toPos]
    # Put it back where it was
    lastMove.fromPos.node.board[lastMove.fromPos] = moved
    let newFromNode = lastMoveInfo.newFromNode
    assert(not newFromNode.isNil)
    newFromNode.unlinkLeaf()

proc getByLatticePos*(g: MCGame, pos: seq[int]): MCLatticeNode[MCBoard] =
  g.nodeLookup.getOrDefault(pos, nil)

## Deserialization with game context
proc toNode*(g: MCGame, n: JsonNode): MCLatticeNode[MCBoard] =
  let arr = n.getElems() # if it's not an array, this will be the
                         # empty array which is fine
  var latticePos: seq[int] = @[]
  for num in arr:
    if num.kind != JInt:
      raise newException(
        ValueError,
        fmt"failed to decode {n}: array value has invalid type")

    latticePos.add(num.getInt())
  result = g.getByLatticePos(latticePos)
  if result.isNil:
    raise newException(ValueError, fmt"failed to locate node at {latticePos}")

proc toPos*(g: MCGame, n: JsonNode): MCPosition =
  result.node = g.toNode(n["node"])
  let fileN = n["file"]
  let rankN = n["rank"]

  if fileN.kind != JInt or rankN.kind != JInt:
    raise newException(
      ValueError,
      fmt"failed to decode {n}: rank and file fields must both be integers")

  result.file = n["file"].getInt()
  result.rank = n["rank"].getInt()

proc toMove*(g: MCGame, n: JsonNode): MCMove =
  result.fromPos = g.toPos(n["fromPos"])
  result.toPos = g.toPos(n["toPos"])
  result.promotion = to(n["promotion"], MCPiece)
