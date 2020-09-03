import latticenodes, boards, moves, moverules, positions, pieces, streams
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
  let moveInfo = move.makeMove()
  var newNodes: seq[MCLatticeNode[MCBoard]]
  newNodes.add(moveInfo.realToNode)
  if not moveInfo.newFromNode.isNil:
     newNodes.add(moveInfo.newFromNode)

  for node in newNodes:
    g.nodeLookup[node.latticePos] = node

  g.moveLog.add(moveInfo)
  return moveInfo.realToNode

proc undoLastMove*(g: var MCGame) =
  if len(g.moveLog) == 0:
    return

  let lastMoveInfo = g.moveLog.pop()
  lastMoveInfo.undoMove()

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
  new result
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
  new result
  result.fromPos = g.toPos(n["fromPos"])
  result.toPos = g.toPos(n["toPos"])
  result.promotion = to(n["promotion"], MCPiece)

type
  GameDumpFormat* = enum
    gdfJson = 'J', gdfTerse = 'T'

  GameLoadError* = object of ValueError

proc write*(stream: Stream, g: MCGame, format = gdfJson) =
  # Magic constant to denote that this is the verbose JSON
  # format. There are plans to add a more terse format in the future,
  # so this will allow for easy backwards compatibility.
  stream.write($char(format))
  stream.writeLine($ %*g.startPosition)
  for info in g.moveLog:
    stream.writeLine($ %*info.move)

proc readGame*(stream: Stream): MCGame =
  let format = GameDumpFormat(stream.readChar())
  case format:
  of gdfJson:
    let startPos = to(parseJson(stream.readLine()), MCBoard)
    result = initGame(startPos)
    var moveLine = ""
    while stream.readLine(moveLine):
      discard result.makeMove(result.toMove(parseJson(moveLine)))
  of gdfTerse:
    raise newException(GameLoadError, "terse game dump format not supported yet, sorry")
  else:
    raise newException(GameLoadError, fmt"invalid game dump format: {format}")
