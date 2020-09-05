{.experimental: "notnil".}

import positions, pieces, latticenodes, boards, playercolors
import combinations
import tables, sequtils, hashes, json, strformat, math

type
  MCMove* = ref MCMoveObj not nil
  MCMoveObj* = object
    fromPos*: MCPosition
    toPos*: MCPosition
    promotion*: MCPiece

  MCMoveInfo* = object
    move*: MCMove
    # The node where the piece is now located
    realToNode*: MCLatticeNode[MCBoard]
    # (Only for time jumps) the node created with a missing piece
    newFromNode*: MCLatticeNode[MCBoard]

  MCMoveRule = proc(node: MCLatticeNode[MCBoard], pos: MCPosition): seq[MCMove]

proc mv*(fromPos: MCPosition, toPos: MCPosition, promotion: MCPiece): MCMove =
  MCMove(fromPos: fromPos, toPos: toPos, promotion: promotion)

proc `$`*(m: MCMove): string =
  fmt"move({m.fromPos} to {m.toPos})"
proc `==`*(m1, m2: MCMove): bool =
  m1.fromPos == m2.fromPos and m1.toPos == m2.toPos and
  m1.promotion == m2.promotion

proc hash*(m: MCMove): Hash =
  var h: Hash = 0
  h = h !& hash(m.fromPos)
  h = h !& hash(m.toPos)
  h = h !& int(m.promotion)
  return !$h

var movementRules = initTable[MCPiece, MCMoveRule]()

template defMovement*(p: MCPiece, body: untyped) {.dirty.} =
  movementRules[p] = proc (node: MCLatticeNode[MCBoard] not nil,
      pos: MCPosition): seq[MCMove] =
    var pos = pos
    pos.node = node
    # utility procs
    template isBlocked(apos: MCPosition): bool {.used.} =
      hasPieceOfSameColor(pos, apos)
    template moveTo(apos: MCPosition): MCMove {.used.} =
      mv(pos, apos, mcpNone)
    template moveToAndPromote(apos: MCPosition, promotion: MCPiece): MCMove {.used.} =
      mv(pos, apos, promotion)

    body

# These have to be templates because the JS backend doesn't support
# inline
template hasPiece*(sq: MCSquare): bool =
  sq.piece != mcpNone

template hasPiece*(p: MCPosition): bool =
  p.getSquare().hasPiece()

template isCapture*(m: MCMove): bool =
  let fromSquare = m.fromPos.getSquare()
  let toSquare = m.toPos.getSquare()
  if not fromSquare.hasPiece:
    false
  else:
    toSquare.hasPiece and toSquare.color != fromSquare.color

template isTimeJump*(m: MCMove): bool =
  m.fromPos.node != m.toPos.node


template hasPieceOfSameColor(p1, p2: MCPosition): bool =
  ## Returns true if p1 and p2 both contain a piece of the same color.
  p1.hasPiece() and p2.hasPiece() and
    p1.getSquare().color == p2.getSquare().color

# Note: I would love to use iterators but closure iterators are NOT
# supported in the JS backend sadly
proc `==>`(prevPositions: seq[MCPosition], dir: (MCAxis, MCAxisDirection)):
         seq[MCPosition] =
  let (d, f) = dir
  for pos in prevPositions:
    for p1 in getAdjacentPositions(pos, d, f):
      result.add(p1)

proc `==>`(pos: MCPosition, dir: (MCAxis, MCAxisDirection)): seq[MCPosition] =
  let (d, f) = dir
  for p1 in getAdjacentPositions(pos, d, f):
    result.add(p1)

iterator possiblePaths(axes: seq[MCAxis]): seq[(MCAxis, MCAxisDirection)] =
  let n = len(axes)
  for bitset in 0 .. 2 ^ n - 1:
    var res: seq[(MCAxis, MCAxisDirection)]
    var x = bitset
    for i in 0 .. n - 1:
      if x mod 2 == 1:
        res.add( (axes[i], mcdUp) )
      else:
        res.add( (axes[i], mcdDown) )
      x = x shr 1
    yield res

proc getPositionsAtPath(pos: MCPosition, path: seq[(MCAxis, MCAxisDirection)]): seq[MCPosition] =
  var prev = @[pos]
  for dir in path:
    when defined(js):
      asm """
`result` = [];
"""
    else:
      result = @[]
    for pos in prev:
      for apos in getAdjacentPositions(pos, dir[0], dir[1]):
        result.add(apos)
    when defined(js):
      asm """
`prev` = `result`;
"""
    else:
      prev = result

proc checkIfPawnMoved(p: MCPosition): bool =
  false  # TODO

iterator iterPositions*(n: MCLatticeNode[MCBoard]): MCPosition =
  let b = n.board
  for f in 0..b.numFiles-1:
    for r in 0..b.numRanks-1:
      yield pos(n, f, r)

proc isLegal*(m: MCMove): bool =
  ## This returns whether a PSEUDO-LEGAL move is legal. Not if just
  ## ANY move is legal, it already has to be pseudo legal. See
  ## `getPseudoLegalMoves`.

  return true


const axisPairs = static:
  toSeq(combinations(mcAxes, 2))
const axisCombos = static:
  assert(len(mcAxes) == 4)
  toSeq(combinations(mcAxes))

iterator getPseudoLegalMoves*(p: MCPosition): MCMove =
  ## Iterate over "pseudo-legal" moves. These include moves that are
  ## allowable by normal chess rules ("knight jumps two in one
  ## direction and one in another direction") but ignores things like
  ## checks
  let square = p.getSquare()
  let piece = square.piece
  if piece in movementRules:
    for move in movementRules[piece](p.node, p):
      yield move

defMovement mcpKnight:
  for d1 in mcAxes:
    for d2 in mcAxes:
      if d1 == d2:
        continue
      for f1 in mcAxisDirections:
        for f2 in mcAxisDirections:
          for p3 in pos ==> (d1, f1) ==> (d1, f1) ==> (d2, f2):
            if not p3.isBlocked:
              result.add(moveTo(p3))

defMovement mcpBishop:
  for dirs in axisPairs:
    # one bishop "move" is going one step in any two distinct axes.
    for f1 in mcAxisDirections:
      for f2 in mcAxisDirections:
        var frontier = @[pos]
        while len(frontier) > 0:
          let cpos = frontier.pop()
          for p2 in cpos ==> (dirs[0], f1) ==> (dirs[1], f2):
            if p2.isBlocked: continue

            let candidateMove = moveTo(p2)
            result.add(candidateMove)
            if not candidateMove.isCapture:
              frontier.add(p2)

defMovement mcpRook:
  for dir in mcAxes:
    for f1 in mcAxisDirections:
      var frontier = @[pos]
      while len(frontier) > 0:
        let cpos = frontier.pop()
        for p1 in cpos ==> (dir, f1):
          if p1.isBlocked: continue

          let candidateMove = moveTo(p1)
          result.add(candidateMove)
          if not candidateMove.isCapture:
            frontier.add(p1)

defMovement mcpQueen:
  # Just in case this changes
  for combo in axisCombos:
    for path in combo.possiblePaths():
      var frontier = @[pos]
      while len(frontier) > 0:
        let cpos = frontier.pop()
        for p1 in cpos.getPositionsAtPath(path):
          if p1.isBlocked: continue

          let candidateMove = moveTo(p1)
          result.add(candidateMove)
          if not candidateMove.isCapture:
            frontier.add(p1)

defMovement mcpKing:
  # TODO: Castling??
  for combo in axisCombos:
    for path in combo.possiblePaths():
      for p1 in pos.getPositionsAtPath(path):
        if p1.isBlocked: continue

        let candidateMove = moveTo(p1)
        result.add(candidateMove)

defMovement mcpPawn:
  # TODO: en passant??

  # Note: it's important whether the pawn is white or black. This is
  # the only piece whose color affects its movement rules. White pawns
  # move up and black pawns move down. Pawns don't move backwards or
  # forwards in time, to respect their "vertical" nature. However,
  # they can capture through time.
  #
  # If a pawn hasn't moved before, it may move forward twice.
  let color = pos.getSquare().color
  let axisDir = if color == mccWhite: mcdUp else: mcdDown
  let numRanks = pos.node.board.numRanks
  let isOnSecondRank = if color == mccWhite:
                         pos.rank == 1
                       else:
                         pos.rank == numRanks - 2

  # Technically, this checks if the pawn originally at `pos` has
  # moved. This is equivalent to asking whether this pawn has moved.
  let alreadyMoved = (not isOnSecondRank) or checkIfPawnMoved(pos)

  # Movement rules
  for dir in [mcaRank, mcaSibling]:
    for cpos in pos ==> (dir, axisDir):
      if cpos.isBlocked: continue

      let candidateMove = moveTo(cpos)
      # Pawns can't capture forward
      if candidateMove.isCapture: continue
      result.add(candidateMove)

      if alreadyMoved: continue

      for ccpos in cpos ==> (dir, axisDir):
        if ccpos.isBlocked: continue
        let candidateMove = moveTo(ccpos)
        if candidateMove.isCapture: continue
        result.add(candidatemove)

  # Capture rules
  for d1 in [mcaRank, mcaSibling]:
    for d2 in [mcaFile, mcaTime]:
      for f1 in mcAxisDirections:
        for cpos in pos ==> (d1, axisDir) ==> (d2, f1):
          let candidateMove = moveTo(cpos)
          if candidateMove.isCapture:
            result.add(candidateMove)

proc `%`*(move: MCMove): JsonNode =
  result = newJObject()
  result.fields["fromPos"] = %move.fromPos
  result.fields["toPos"] = %move.toPos
  result.fields["promotion"] = %move.promotion
