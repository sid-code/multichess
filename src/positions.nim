import latticenodes, boards
import hashes, strformat

type
  MCPosition* = ref MCPositionObj
  MCPositionObj* = object
    node*: MCLatticeNode[MCBoard]
    file*: int
    rank*: int

proc hash*(p: MCPosition): Hash =
  var h: Hash = 0
  h = h !& hash(p.node.latticePos)
  h = h !& p.file
  h = h !& p.rank
  return !$h

proc pos*(node: MCLatticeNode, file: int, rank: int): MCPosition =
  if isNil(node):
    raise newException(ValueError, "cannot construct position with nil node")
  else:
    new result
    result.node = node
    result.file = file
    result.rank = rank

proc `$`*(p: MCPosition): string =
  fmt"[{p.node}: {p.file}, {p.rank}]"

proc `==`*(p1, p2: MCPosition): bool =
  p1.node == p2.node and p1.file == p2.file and p1.rank == p2.rank

iterator getAdjacentPositions*(pos: MCPosition, dir: MCAxis,
    cdir: MCAxisDirection): MCPosition =
  # Axes orientation (which direction is cdir == mcdUp):
  # rank: right, file: up, time: forward, sibling: next sibling
  let node = pos.node
  let file = pos.file
  let rank = pos.rank
  case dir:
    of mcaRank:
      if cdir == mcdUp:
        if rank < node.board.numRanks-1:
          yield pos(node, file, rank+1)
      else:
        if rank > 0:
          yield pos(node, file, rank-1)

    of mcaFile:
      if cdir == mcdUp:
        if file < node.board.numFiles-1:
          yield pos(node, file+1, rank)
      else:
        if file > 0:
          yield pos(node, file-1, rank)

    of mcaTime:
      if cdir == mcdUp:
        for future in node.future:
          for future2 in future.future:
            if not isNil(future2):
              yield pos(future2, file, rank)
      else:
        let past = node.past
        if not isNil(past):
          let past2 = past.past
          if not isNil(past2):
            yield pos(past2, file, rank)

    of mcaSibling:
      if cdir == mcdUp:
        let prevSibling = node.prevSibling
        if not isNil(prevSibling):
          yield pos(prevSibling, file, rank)
      else:
        let nextSibling = node.nextSibling
        if not isNil(nextSibling):
          yield pos(nextSibling, file, rank)

proc `[]=`*(b: var MCBoard, p: MCPosition, newSquare: MCSquare) =
  b[p.file, p.rank] = newSquare

proc `[]`*(b: MCBoard, p: MCPosition): MCSquare =
  b[p.file, p.rank]

proc getSquare*(p: MCPosition): MCSquare =
  p.node.board[p]

proc setSquare*(p: MCPosition, newSquare: MCSquare) =
  p.node.board[p] = newSquare
