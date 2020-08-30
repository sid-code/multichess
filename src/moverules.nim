import latticenodes, boards, moves, positions, playercolors, pieces
import tables

iterator getAllPossibleMoves(rootNode: MCLatticeNode[MCBoard]): MCMove =
  for node in rootNode.getNodesNeedingMove():
    for pos in node.iterPositions():
      for move in pos.getPseudoLegalMoves():
        yield move

iterator getAllPseudoLegalMoves(rootNode: MCLatticeNode[MCBoard],
                                otherPlayer = false): MCMove =
  for node in rootNode.getNodesNeedingMove():
    for pos in node.iterPositions():
      if otherPlayer xor (node.board.toPlay == pos.getSquare().color):
        for move in pos.getPseudoLegalMoves():
          yield move

proc isMoveBlatantlyIllegal(m: MCMove): bool =
  ## Returns true if a move is blatantly illegal. "Blatantly illegal"
  ## means either the piece trying to be moved doesn't exist, or it's
  ## trying to move onto a piece of its same color. Or, it's not that
  ## piece's color's turn.

  let fromPos = m.fromPos
  let toPos = m.toPos
  let fromSquare = fromPos.getSquare()
  let toSquare = toPos.getSquare()

  if not fromPos.hasPiece():
    return true

  # not your turn
  if fromPos.node.board.toPlay != fromSquare.color:
    return true

  # piece trying to move onto piece of same color
  if toSquare.hasPiece and toSquare.color == fromSquare.color:
    return true

proc makeMove*(move: MCMove): seq[MCLatticeNode[MCBoard]] =
  let fromPos = move.fromPos
  let toPos = move.toPos
  let square = fromPos.getSquare()
  let fromNode = fromPos.node
  let toNode = toPos.node
  let otherPlayer = oppositeColor(square.color)

  let preferredSiblingDirection = 
    if square.color == mccWhite:
      mclsPrev
    else:
      mclsNext

  var bcopy = toNode.board

  if not move.isTimeJump:
    bcopy[fromPos.file, fromPos.rank] = (mcpNone, mccWhite)

  bcopy[toPos.file, toPos.rank] = square
  bcopy.toPlay = otherPlayer

  result.add(toPos.node.branch(bcopy, preferredSiblingDirection))

  if move.isTimeJump:
    let newFromNode = fromNode.branch(fromNode.board, preferredSiblingDirection)
    newFromNode.board[fromPos.file, fromPos.rank] = (mcpNone, mccWhite)
    newFromNode.board.toPlay = otherPlayer
    result.add(newFromNode)

proc checksInPosition*(rootNode: MCLatticeNode[MCBoard]): seq[MCMove] =
  for move in rootNode.getAllPossibleMoves():
    let fromSquare = move.fromPos.getSquare()
    let toSquare = move.toPos.getSquare()
    if toSquare.piece == mcpKing and fromSquare.color == oppositeColor(toSquare.color):
      result.add(move)

iterator getAllLegalMoves*(rootNode: MCLatticeNode[MCBoard]): MCMove =
  for move in rootNode.getAllPseudoLegalMoves():
    if move.isMoveBlatantlyIllegal():
      continue

    var moveCopy = move
    var nodeCopies = initTable[seq[int], MCLatticeNode[MCBoard]]()
    let rootNodeCopy = deepCopyTree(rootNode, nodeCopies)
    moveCopy.fromPos.node = nodeCopies[move.fromPos.node.latticePos]
    moveCopy.toPos.node = nodeCopies[move.toPos.node.latticePos]
    assert not moveCopy.fromPos.node.isNil
    assert not moveCopy.toPos.node.isNil
    discard moveCopy.makeMove()

    var isIllegal = false

    let checks = rootNodeCopy.checksInPosition()
    let fromColor = moveCopy.fromPos.getSquare().color
    for check in checks:
      if check.toPos.getSquare().color == fromColor:
        isIllegal = true

    if not isIllegal:
      yield move
