import tables, strutils, json
import pieces, playercolors

type
  MCSquare* = tuple
    ## The name of the piece (if any) that is occupying this square
    piece: MCPiece
    ## The color of the piece occupying this square
    color: MCPlayerColor

  MCBoard* = object
    numFiles*: int
    numRanks*: int
    toPlay*: MCPlayerColor
    squares*: seq[MCSquare]

  MCAxis* = enum
    mcaRank, mcaFile, mcaTime, mcaSibling

  MCAxisDirection* = enum
    mcdUp, mcdDown

const mcAxes* = [mcaRank, mcaFile, mcaTime, mcaSibling]
const mcAxisDirections* = [mcdUp, mcdDown]

proc getPieceChar(p: MCPiece): string =
  case p:
  of mcpNone: "."
  of mcpPawn: "p"
  of mcpKnight: "n"
  of mcpBishop: "b"
  of mcpRook: "r"
  of mcpQueen: "q"
  of mcpKing: "k"

proc initBlankBoard*(numFiles, numRanks: int, toPlay = mccWhite): MCBoard =
  result.numRanks = numRanks
  result.numFiles = numFiles
  result.toPlay = toPlay
  result.squares = newSeq[MCSquare](numRanks * numFiles)

proc `[]`*(b: MCBoard, file: int, rank: int): MCSquare =
  b.squares[file * b.numRanks + rank]

proc `[]=`*(b: var MCBoard, file: int, rank: int, newSquare: MCSquare) =
  b.squares[file * b.numRanks + rank] = newSquare

proc `$`*(p: MCSquare): string =
  let pc = getPieceChar(p.piece)
  if p.color == mccWhite:
    return pc.toUpper()
  else:
    return pc

proc `$`*(b: MCBoard): string =
  for r in countdown(b.numRanks-1, 0):
    for f in countup(0, b.numFiles-1):
      result &= $b[f, r]
    result &= "\n"
  if b.toPlay == mccWhite:
    result &= "White to play."
  else:
    result &= "Black to play."

proc `%`*(b: MCSquare): JsonNode =
  result = newJObject()
  result.fields["piece"] = %b.piece
  result.fields["color"] = %b.color

  
  
  
