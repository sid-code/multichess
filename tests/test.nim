import unittest
import latticenodes, boards, games, pieces, positions, playercolors, moves, moverules, startpos, layouts
import sequtils, tables, streams
from sugar import `=>`

suite "piece movement":
  setup:
    let f = 5
    let r = 5
    let squares = newSeq[MCSquare](f * r)
    let sp = MCBoard(numFiles: 5, numRanks: 5, squares: squares)
    var g = initGame(sp)

  test "knight moves":
    let kp = pos(g.rootNode, 2, 2)
    kp.setSquare((mcpKnight, mccWhite))
    let moves = toSeq(getPseudoLegalMoves(kp))
    let movePositions = moves.map(m => (m.toPos.file, m.toPos.rank))

    # some sanity checks
    for move in moves:
      check(move.fromPos == kp)
      check(move.toPos.node == move.fromPos.node)

    check(len(moves) == 8)
    check((0, 1) in movePositions)
    check((0, 3) in movePositions)
    check((1, 0) in movePositions)
    check((1, 4) in movePositions)
    check((3, 0) in movePositions)
    check((3, 4) in movePositions)
    check((4, 1) in movePositions)
    check((4, 3) in movePositions)

  test "bishop moves":
    let bp = pos(g.rootNode, 2, 2)
    bp.setSquare((mcpBishop, mccWhite))
    let moves = toSeq(getPseudoLegalMoves(bp))
    let movePositions = moves.map(m => (m.toPos.file, m.toPos.rank))

    check(len(moves) == 8)
    check((0, 0) in movePositions)
    check((1, 1) in movePositions)
    check((3, 3) in movePositions)
    check((4, 4) in movePositions)
    check((0, 4) in movePositions)
    check((1, 3) in movePositions)
    check((3, 1) in movePositions)
    check((4, 0) in movePositions)

  test "rook moves":
    let rp = pos(g.rootNode, 2, 2)
    rp.setSquare((mcpRook, mccWhite))
    let moves = toSeq(getPseudoLegalMoves(rp))
    let movePositions = moves.map(m => (m.toPos.file, m.toPos.rank))
    check(len(moves) == 8)

    check((2, 0) in movePositions)
    check((2, 1) in movePositions)
    check((2, 3) in movePositions)
    check((2, 4) in movePositions)
    check((0, 2) in movePositions)
    check((1, 2) in movePositions)
    check((3, 2) in movePositions)
    check((4, 2) in movePositions)

  test "queen moves":
    let qp = pos(g.rootNode, 2, 2)
    qp.setSquare((mcpQueen, mccWhite))
    let moves = toSeq(getPseudoLegalMoves(qp))
    let movePositions = moves.map(m => (m.toPos.file, m.toPos.rank))
    check(len(moves) == 16)

    check((0, 0) in movePositions)
    check((1, 1) in movePositions)
    check((3, 3) in movePositions)
    check((4, 4) in movePositions)
    check((0, 4) in movePositions)
    check((1, 3) in movePositions)
    check((3, 1) in movePositions)
    check((4, 0) in movePositions)
    check((2, 0) in movePositions)
    check((2, 1) in movePositions)
    check((2, 3) in movePositions)
    check((2, 4) in movePositions)
    check((0, 2) in movePositions)
    check((1, 2) in movePositions)
    check((3, 2) in movePositions)
    check((4, 2) in movePositions)

  test "king moves":
    let kp = pos(g.rootNode, 2, 2)
    kp.setSquare((mcpKing, mccWhite))
    let moves = toSeq(getPseudoLegalMoves(kp))
    let movePositions = moves.map(m => (m.toPos.file, m.toPos.rank))
    check(len(moves) == 8)

    check((1, 1) in movePositions)
    check((1, 2) in movePositions)
    check((1, 3) in movePositions)
    check((2, 1) in movePositions)
    check((2, 3) in movePositions)
    check((3, 1) in movePositions)
    check((3, 2) in movePositions)
    check((3, 3) in movePositions)

  test "bishop moves, blocked by knight":
    let bp = pos(g.rootNode, 2, 2)
    let kp = pos(g.rootNode, 3, 3)
    bp.setSquare((mcpBishop, mccWhite))
    kp.setSquare((mcpKnight, mccWhite))
    let moves = toSeq(getPseudoLegalMoves(bp))

    check(len(moves) == 6)

  test "bishop moves, capturing knight":
    let bp = pos(g.rootNode, 2, 2)
    let kp = pos(g.rootNode, 3, 3)
    bp.setSquare((mcpBishop, mccWhite))
    kp.setSquare((mcpKnight, mccBlack))
    let moves = toSeq(getPseudoLegalMoves(bp))
    let movePositions = moves.map(m => (m.toPos.file, m.toPos.rank))

    check(len(moves) == 7)
    check((3, 3) in movePositions)

suite "timelines":
  setup:
    let f = 5
    let r = 5
    let squares = newSeq[MCSquare](f * r)
    let sp = MCBoard(numFiles: 5, numRanks: 5, squares: squares)
    let root = newLatticeNode[MCBoard](sp)

  test "branched nodes have the correct siblings":
    let b2 = sp
    let n1 = root.branch(b2, mclsNext)
    let n2 = root.branch(b2, mclsNext)
    check(root.future == @[n1, n2])
    check(len(n1.future) == 0)
    check(len(n2.future) == 0)
    check(n1.nextSibling == n2)
    check(n1.prevSibling.isNil)
    check(n2.prevSibling == n1)
    check(n2.nextSibling.isNil)

  test "branched nodes have the correct siblings v2":
    let n1 = root.branch(sp, mclsNext)
    let n11 = n1.branch(sp, mclsNext)
    let n111 = n11.branch(sp, mclsNext)
    let n2 = root.branch(sp, mclsNext)
    check(n2.prevSibling == n1)
    let n21 = n2.branch(sp, mclsNext)
    check(n21.prevSibling == n11)
    let n23 = n2.branch(sp, mclsPrev)
    check(n23.prevSibling == n11)
    check(n21.prevSibling == n23)


  test "branched nodes arrange themselves properly":
    let n1 = root.branch(sp, mclsNext)
    let n11 = n1.branch(sp, mclsNext)
    let n12 = n1.branch(sp, mclsNext)
    let n111 = n11.branch(sp, mclsNext)
    let n121 = n12.branch(sp, mclsNext)

    check(n111.nextSibling == n121)

  test "branched nodes arrange themselves properly v2":
    var g = initGame(mcKQOnly5x5)
    let n0 = g.rootNode
    let n1 = g.makeMove(mv(pos(n0, 1, 0), pos(n0, 3, 0), mcpNone))
    let n2 = g.makeMove(mv(pos(n1, 1, 4), pos(n1, 3, 4), mcpNone))
    let n3 = g.makeMove(mv(pos(n2, 3, 0), pos(n0, 3, 0), mcpNone))
    let n4 = g.makeMove(mv(pos(n3, 1, 4), pos(n1, 2, 3), mcpNone))
    let n5 = g.makeMove(mv(pos(n4, 3, 0), pos(n0, 4, 0), mcpNone))
    check(g.rootNode.future[0] ==
          g.rootNode.future[0].prevSibling.prevSibling.nextSibling.nextSibling)

suite "game logic":
  setup:
    let f = 5
    let r = 5
    let squares = newSeq[MCSquare](f * r)
    let sp = MCBoard(numFiles: 5, numRanks: 5, squares: squares)
    let root = newLatticeNode[MCBoard](sp)

  test "TODO: knight moves on clear board":
    var osp = sp
    osp[2, 2] = (mcpKnight, mccWhite)
    osp[2, 4] = (mcpKnight, mccBlack)
    osp.toPlay = mccWhite
    var game = initGame(osp)
    let kp = pos(game.rootNode, 2, 2)
    var moves = toSeq(game.rootNode.getAllLegalMoves())
    let n1 = game.makeMove(moves[0])
    moves = toSeq(game.rootNode.getAllLegalMoves())
    let n2 = game.makeMove(moves[0])

  test "king is in check":
    var osp = sp
    osp[2, 2] = (mcpKing, mccWhite)
    osp[1, 1] = (mcpKnight, mccWhite)
    osp[2, 4] = (mcpRook, mccBlack)
    osp.toPlay = mccWhite
    let game = initGame(osp)
    let moves = toSeq(game.rootNode.getAllLegalMoves())
    for move in moves:
      # The knight must block the check
      if move.fromPos == pos(game.rootNode, 1, 1):
        check move.toPos == pos(game.rootNode, 2, 3)
      if move.fromPos == pos(game.rootNode, 2, 2):
        check move.toPos != pos(game.rootNode, 2, 1)
        check move.toPos != pos(game.rootNode, 2, 3)

suite "layout":
  setup:
    var game = initGame(mcStartPos5x5)
    var game2 = initGame(mcKQOnly5x5)

  test "simple branched position layout works":
    let m0 = game.rootNode
    let m1 = game.makeMove(mv(pos(m0, 2, 1), pos(m0, 2, 2), mcpNone))
    let m2 = game.makeMove(mv(pos(m1, 3, 3), pos(m1, 3, 2), mcpNone))
    let m3 = game.makeMove(mv(pos(m2, 3, 0), pos(m0, 3, 2), mcpNone))
    check(not m3.nextSibling.isNil)
    # m3 is the node with the extra white knight
    let m4 = game.makeMove(mv(pos(m3, 3, 4), pos(m1, 3, 2), mcpNone))
    let m5 = game.makeMove(mv(pos(m4, 3, 0), pos(m0, 3, 2), mcpNone))

    #let l = layout(game.rootNode)
    # TODO: test something here

suite "game dumps":
  setup:
    var game = initGame(mcKQOnly5x5)
    let m0 = game.rootNode
    let m1 = game.makeMove(mv(pos(m0, 2, 1), pos(m0, 2, 2), mcpNone))
    let m2 = game.makeMove(mv(pos(m1, 3, 3), pos(m1, 3, 2), mcpNone))
    let m3 = game.makeMove(mv(pos(m2, 3, 0), pos(m0, 3, 2), mcpNone))
    let m4 = game.makeMove(mv(pos(m3, 3, 4), pos(m1, 3, 2), mcpNone))
    let m5 = game.makeMove(mv(pos(m4, 3, 0), pos(m0, 3, 2), mcpNone))

  test "game dump/load preserves layout":
    let l = layout(game.rootNode)

    var stream = newStringStream()
    stream.write(game)
    var readStream = newStringStream(stream.data)
    let gameCopy = readStream.readGame()

    let lc = layout(gameCopy.rootNode)

    for np, node in l.placement:
      check(lc.placement[np].latticePos == node.latticePos)

suite "misc":
  setup:
    var game = initGame(mcKQOnly5x5)

  test "deepcopy preserves layout":
    let m0 = game.rootNode
    let m1 = game.makeMove(mv(pos(m0, 2, 1), pos(m0, 2, 2), mcpNone))
    let m2 = game.makeMove(mv(pos(m1, 3, 3), pos(m1, 3, 2), mcpNone))
    let m3 = game.makeMove(mv(pos(m2, 3, 0), pos(m0, 3, 2), mcpNone))
    let m4 = game.makeMove(mv(pos(m3, 3, 4), pos(m1, 3, 2), mcpNone))
    let m5 = game.makeMove(mv(pos(m4, 3, 0), pos(m0, 3, 2), mcpNone))

    let l = layout(game.rootNode)

    var nodeCopies = initTable[seq[int], MCLatticeNode[MCBoard]]()
    let rootNodeCopy = deepCopyTree(game.rootNode, nodeCopies)
    let lc = layout(rootNodeCopy)

    for np, node in l.placement:
      check(lc.placement[np].latticePos == node.latticePos)
