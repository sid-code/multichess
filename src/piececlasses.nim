import strformat
import boards, pieces, playercolors

proc getClassFor*(s: MCSquare): cstring =
  let piece = s.piece
  let color = s.color
  let pieceClassStr = case piece:
                        of mcpKing:
                          "king"
                        of mcpQueen:
                          "queen"
                        of mcpRook:
                          "rook"
                        of mcpBishop:
                          "bishop"
                        of mcpKnight:
                          "knight"
                        of mcpPawn:
                          "pawn"
                        of mcpNone:
                          "none"
  let colorClassStr = case color:
                        of mccWhite:
                          "white"
                        of mccBlack:
                          "black"

  return cstring(fmt"piece piece-{pieceClassStr}-{colorClassStr}")
