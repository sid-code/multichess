import boards, games, pieces, playercolors, positions, moves, latticenodes, layouts, startpos, moverules

# simple test program
when isMainModule:
  let f = 5
  let r = 5
  let squares = newSeq[MCSquare](f * r)
  var sp = MCBoard(numFiles: 5, numRanks: 5, squares: squares)

  sp[0, 0] = (mcpKnight, mccWhite)

  let g = newGame(sp)
  let kp = pos(g.rootNode, 0, 0)
  echo g.rootNode.board
