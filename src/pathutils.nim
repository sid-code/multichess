import boards, positions, latticenodes
import sequtils

type
  MCPositionIterator* = object
    start: MCPosition
    path: MCPath
    plen: int
    opts: seq[seq[MCPosition]]
    idxs: seq[int]
    pos: int
    done: bool

proc initMCPositionIterator(p: MCPosition, path: MCPath): MCPositionIterator =
  result.start = p
  result.path = path
  result.plen = len(path)
  result.opts = newSeq[seq[MCPosition]](result.plen)
  result.idxs = newSeq[int](result.plen)
  result.pos = 0
  result.done = false

proc next(it: var MCPositionIterator): MCPosition =
  if it.done: return nil

  #echo "NEXT ", it
  while it.pos < it.plen:
    let fp = if it.pos == 0:
               it.start
             else:
               if len(it.opts[it.pos - 1]) == 0:
                 it.idxs[it.pos] = 0
                 it.opts[it.pos].setLen(0)
                 it.pos += 1
                 continue

               it.opts[it.pos - 1][it.idxs[it.pos - 1]]

    let (ax, dir) = it.path[it.pos]
    #echo ax, " ", dir, " ", fp
    it.opts[it.pos] = toSeq(fp.getAdjacentPositions(ax, dir))
    it.pos += 1

  if it.pos == it.plen:
    it.pos -= 1
    #echo "SPIT ", it
    if it.idxs[it.pos] < len(it.opts[it.pos]):
      result = it.opts[it.pos][it.idxs[it.pos]]
    it.idxs[it.pos] += 1

    while it.idxs[it.pos] == len(it.opts[it.pos]):
      it.idxs[it.pos] = 0
      it.opts[it.pos].setLen(0)
      it.pos -= 1
      if it.pos >= 0:
        it.idxs[it.pos] += 1
        #echo "INC ", it
      else:
        it.done = true
        break
  
import macros
macro gpap*(p: typed, paths: static[seq[MCPath]], v: untyped, body: untyped): untyped =
  expectKind(v, nnkIdent)
  result = newStmtList()
  for path in paths:
    var forStmts: seq[NimNode]
    var syms: seq[NimNode]
    var forStmt: NimNode = nil
    for (ax, dir) in path:
      let sym = genSym(nskForVar, "p")
      syms.add(sym)
      forStmt = newNimNode(nnkForStmt)
      forStmt.add(sym)
      forStmt.add(newCall(bindSym("getAdjacentPositions"),
                          p, newLit(ax), newLit(dir)))
      # we leave off the body
      forStmts.add(forStmt)
    for i in 1 .. len(forStmts) - 1:
      forStmts[i - 1].add(forStmts[i])

    var bodyStmts = newStmtList()
    bodyStmts.add(newLetStmt(v, syms[^1]))
    bodyStmts.add(body)
    forStmts[^1].add(bodyStmts)

    result.add(forStmts[0])

const ps = @[ @[(mcaTime, mcdUp), (mcaRank, mcdUp)], @[(mcaTime, mcdDown), (mcaRank, mcdDown)] ]

iterator getPositionsAtPath*(p: MCPosition, path: MCPath): MCPosition =
  var it = initMCPositionIterator(p, path)
  while not it.done:
    let fp = it.next()
    if fp.isNil:
      break
    yield fp

when isMainModule:
  import startpos, games
  let g = newGame(mcStartPos5x5)
  let n1 = g.rootNode.branch(mcStartPos5x5, mclsNext)
  # Two futures
  let n2 = n1.branch(mcStartPos5x5, mclsNext)
  let n3 = n1.branch(mcStartPos5x5, mclsNext)
  let p = pos(g.rootNode, 0, 0)

  expandMacros:
    gpap(p, ps, ap):
      echo ap
