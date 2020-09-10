# Serialization.

import streams, bitops
import latticenodes, boards, games, moves, positions, pieces, playercolors

type
  GameDumpFormat* = enum
    gdfJson = 'J', gdfTerse = 'T'

  GameLoadError* = object of ValueError

proc write*(stream: Stream, i: uint8) =
  stream.write($char(i))

proc write*(stream: Stream, i: uint32) =
  var str: string
  str.add(char(bitand(i shr 24, 0xFF)))
  str.add(char(bitand(i shr 16, 0xFF)))
  str.add(char(bitand(i shr 8, 0xFF)))
  str.add(char(bitand(i, 0xFF)))
  stream.write(str)

proc readUint8*(stream: Stream): uint8 =
  let buf = stream.readStr(1)
  return uint8(buf[0])

proc readUint32*(stream: Stream): uint32 =
  let size = sizeof uint32
  let buf = stream.readStr(size)
  var cs: seq[uint8]
  for c in buf:
    result = result * 256
    result = result + uint32(c)

proc writeStrAndLen*(stream: Stream, str: string) =
  stream.write(uint32(len(str)))
  stream.write(str)

proc readStrAndLen*(stream: Stream): string =
  let nbytes = stream.readUint32()
  result = stream.readStr(int(nbytes))

proc write(stream: Stream, p: MCLatticePos) =
  let pz = cast[seq[int]](p)
  stream.write(uint32(pz.len))
  for x in pz:
    stream.write(uint32(x))

proc read(stream: Stream, o: var MCLatticePos) =
  var pz: seq[int]
  let size = int(serialization.readUint32(stream))
  for _ in 0 ..< size:
    pz.add(int(serialization.readUint32(stream)))
  o = MCLatticePos(pz)

proc write*(stream: Stream, p: MCPosition) =
  stream.write(p.node.latticePos)
  stream.write(uint32(p.file))
  stream.write(uint32(p.rank))

proc read*(stream: Stream, g: MCGame, o: var MCPosition) =
  var lp: MCLatticePos
  stream.read(lp)
  let node = g.getByLatticePos(lp)
  let file = int(serialization.readUint32(stream))
  let rank = int(serialization.readUint32(stream))
  o = pos(node, file, rank)

proc write*(stream: Stream, m: MCMove) =
  stream.write(m.fromPos)
  stream.write(m.toPos)
  stream.write(uint8(m.promotion))
proc read*(stream: Stream, g: MCGame, m: var MCMove) =
  var fromPos: MCPosition
  var toPos: MCPosition
  stream.read(g, fromPos)
  stream.read(g, toPos)
  let promotion = MCPiece(stream.readUint8())
  m = mv(fromPos, toPos, promotion)

proc write*(stream: Stream, b: MCBoard) =
  stream.write(uint32(b.numFiles))
  stream.write(uint32(b.numRanks))
  stream.write(uint8(b.toPlay))
  for sq in b.squares:
    stream.write(uint8(sq.piece))
    stream.write(uint8(sq.color))
proc read*(stream: Stream, b: var MCBoard) =
  b.numFiles = int(serialization.readUint32(stream))
  b.numRanks = int(serialization.readUint32(stream))
  b.toPlay = MCPlayerColor(stream.readUint8())
  for _ in 0 ..< b.numFiles*b.numRanks:
    let piece = MCPiece(stream.readUint8())
    let color = MCPlayerColor(stream.readUint8())
    b.squares.add((piece, color))

proc write*(stream: Stream, g: MCGame) =
  stream.write($char(gdfTerse))
  stream.write(g.startPosition)
  stream.write(uint32(len(g.moveLog)))
  for info in g.moveLog:
    stream.write(info.move)

proc readGame*(stream: Stream): MCGame =
  let format = GameDumpFormat(stream.readChar())
  case format:
  of gdfTerse:
    var startPos: MCBoard
    stream.read(startPos)
    result = newGame(startPos)
    let numMoves = serialization.readUint32(stream)
    for _ in 0 ..< numMoves: 
      var move: MCMove
      stream.read(result, move)
      discard result.makeMove(move)
  of gdfJson:
    raise newException(GameLoadError, "json format no longer supported")
