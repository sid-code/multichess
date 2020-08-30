import boards, pieces, playercolors

proc addPawns(board: var MCBoard) =
  for file in countup(0, board.numFiles - 1):
    board[file, 1] = (mcpPawn, mccWhite)
    board[file, board.numRanks-2] = (mcpPawn, mccBlack)

proc addPieces(board: var MCBoard, rank: int, color: MCPlayerColor) =
  let numPieces = board.numFiles
  let pieces = case numPieces
               of 5:
                 @[mcpKing, mcpQueen, mcpBishop, mcpKnight, mcpRook]
               of 6:
                 @[mcpRook, mcpKing, mcpQueen, mcpBishop, mcpKnight, mcpRook]
               of 7:
                 @[mcpRook, mcpKnight, mcpQueen, mcpKing, mcpBishop, mcpKnight, mcpRook]
               of 8:
                 @[mcpRook, mcpKnight, mcpBishop, mcpQueen, mcpKing, mcpBishop, mcpKnight, mcpRook]
               else:
                 @[]
                 

  if len(pieces) == 0:
    return
  for i, piece in pieces:
    board[i, rank] = (piece, color)

proc addPieces(board: var MCBoard) =
  board.addPieces(rank=0, color=mccWhite)
  board.addPieces(rank=board.numRanks - 1, color=mccBlack)

const mcStartPos5x5* = static:
  var b = initBlankBoard(5, 5)
  b.addPawns()
  b.addPieces()
  b
const mcKQOnly5x5* = static:
  var b = initBlankBoard(5, 5)
  b[0, 0] = (mcpKing, mccWhite)
  b[1, 0] = (mcpQueen, mccWhite)
  b[0, 4] = (mcpKing, mccBlack)
  b[1, 4] = (mcpQueen, mccBlack)
  b
