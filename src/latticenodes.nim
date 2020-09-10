import tables, hashes, strutils, strformat

# gotta use a generic because of the circular dependency :/
type
  MCLatticePos* = distinct seq[int]
  MCLatticeNode*[T] = ref object
    board*: T
    latticePos*: MCLatticePos
    nextSibling*, prevSibling*: MCLatticeNode[T]
    past*: MCLatticeNode[T]
    future*: seq[MCLatticeNode[T]]


  MCLSiblingDirection* = enum
    mclsNext, mclsPrev
const
  mcRootNodePos* = MCLatticePos(@[])

proc `hash`*(p: MCLatticePos): Hash {.borrow.}
proc `$`*(p: MCLatticePos): string {.borrow.}
proc `==`*(p, q: MCLatticePos): bool {.borrow.}
proc `len`(p: MCLatticePos): Hash {.borrow.}
proc `&`(p, q: MCLatticePos): MCLatticePos {.borrow.}
proc `&`(p: MCLatticePos, q: int): MCLatticePos {.borrow.}

proc `$`*[T](n: MCLatticeNode[T]): string =
  if n.isNil: return "[NULL NODE]"

  let idstr = if n.latticePos.len > 0:
                $n.latticePos
              else:
                "root"

  return fmt"[Node {idstr}]"

proc needsMove*[T](node: MCLatticeNode[T]): bool =
  len(node.future) == 0

iterator allNodes*[T](root: MCLatticeNode[T]): MCLatticeNode[T] =
  var frontier = @[root]
  while len(frontier) > 0:
    var node = frontier.pop()
    yield node
    frontier.add(node.future)

proc newLatticeNode*[T](board: T, nextSibling, prevSibling: MCLatticeNode[T] = nil,
                        past: MCLatticeNode[T] = nil): MCLatticeNode[T] =
  new result
  result.board = board
  result.latticePos = mcRootNodePos
  result.nextSibling = nextSibling
  result.prevSibling = prevSibling
  result.past = past
  result.future = @[]

proc deepCopyTree*[T](node: MCLatticeNode[T],
                   memo: var Table[MCLatticePos, MCLatticeNode[T]]):
                     MCLatticeNode[T] =
  if node.latticePos in memo:
    return memo[node.latticePos]

  result = newLatticeNode(node.board)
  result.latticePos = node.latticePos
  memo[result.latticePos] = result

  if not node.nextSibling.isNil:
    result.nextSibling = deepCopyTree(node.nextSibling, memo)

  if not node.prevSibling.isNil:
    result.prevSibling = deepCopyTree(node.prevSibling, memo)

  if not node.past.isNil:
    result.past = deepCopyTree(node.past, memo)

  for child in node.future:
    result.future.add(deepCopyTree(child, memo))

proc getNodesNeedingMove*[T](node: MCLatticeNode[T]): seq[MCLatticeNode[T]] =
  if needsMove(node):
    result.add(node)
  else:
    for futureNode in node.future:
      result.add(futureNode.getNodesNeedingMove())

proc hash*[T](n: MCLatticeNode[T]): Hash =
  hash(n.latticePos)


proc toDot*[T](node: MCLatticeNode[T]): string =

  var edges: seq[(MCLatticeNode[T], MCLatticeNode[T], string)]

  var frontier = @[node]
  while len(frontier) > 0:
    let n = frontier.pop()

    if not n.past.isNil:
      edges.add((n.past, n, ""))
    if not n.nextSibling.isNil:
      edges.add((n, n.nextSibling, "next"))
    if not n.prevSibling.isNil:
      edges.add((n, n.prevSibling, "prev"))

    for fn in n.future:
      frontier.insert(fn, 0)

  proc getNodeLabel[T](n: MCLatticeNode[T]): string =
    if n.latticePos.len == 0:
      return "root"
    else:
      return n.latticePos.join("")
  result &= "digraph {\n"
  for (to, frm, label) in edges:
    result &= fmt"  {getNodeLabel(to)} -> {getNodeLabel(frm)} [label='{label}'];"
    result &= "\n"
  result &= "}"

template lastElementInLinkedList(list: typed, nextPointer: untyped): untyped =
  var conductor = list
  while not conductor.`nextPointer`.isNil:
    conductor = conductor.`nextPointer`

  conductor

proc joinSiblings[T](x, y: MCLatticeNode[T], extend: MCLSiblingDirection) =
  if x == y: return

  let oldNextSibling = x.nextSibling
  let oldPrevSibling = y.prevSibling
  x.nextSibling = y
  if extend == mclsPrev:
    x.prevSibling = oldPrevSibling
    if not oldPrevSibling.isNil:
      oldPrevSibling.nextSibling = x
  y.prevSibling = x
  if extend == mclsNext:
    y.nextSibling = oldNextSibling
    if not oldNextSibling.isNil:
      oldNextSibling.prevSibling = y

proc branch*[T](node: MCLatticeNode[T], board: T,
                preferSiblingDirection: MCLSiblingDirection): MCLatticeNode[T] =
  let nextSibling = node.nextSibling
  let prevSibling = node.prevSibling

  result = newLatticeNode(board)
  result.latticePos = node.latticePos & len(node.future)
  result.past = node

  if len(node.future) > 0:
    let future = node.future[0]
    if preferSiblingDirection == mclsNext:
      joinSiblings(future, result, mclsNext)
    else:
      joinSiblings(result, future, mclsPrev)
  else:
    if not prevSibling.isNil and len(prevSibling.future) > 0:
      joinSiblings(prevSibling.future[0], result, mclsNext)
    elif not nextSibling.isNil and len(nextSibling.future) > 0:
      joinSiblings(result, nextSibling.future[0], mclsPrev)

  node.future.add(result)
  assert(len(result.latticePos) > 0)

proc unlinkLeaf*[T](leafNode: MCLatticeNode[T]) =
  if leafNode.past.isNil: return
  assert(len(leafNode.future) == 0, "cannot unlink node that is not a leaf")

  # using del because order doesn't matter here
  leafNode.past.future.del(leafNode.past.future.find(leafNode))
  leafNode.past = nil
  if not leafNode.nextSibling.isNil:
    leafNode.nextSibling.prevSibling = leafNode.prevSibling
  if not leafNode.prevSibling.isNil:
    leafNode.prevSibling.nextSibling = leafNode.nextSibling

  leafNode.nextSibling = nil
  leafNode.prevSibling = nil

when isMainModule:
  import boards
  let f = 5
  let r = 5
  let squares = newSeq[MCSquare](f * r)
  let sp = MCBoard(numFiles: 5, numRanks: 5, squares: squares)
  let root = newLatticeNode[MCBoard](sp)

  let b2 = sp
  let n1 = root.branch(b2, mclsNext)
  let n2 = root.branch(b2, mclsNext)
  let n3 = n2.branch(b2, mclsNext)
  let n4 = n2.branch(b2, mclsNext)
  let n5 = n3.branch(b2, mclsNext)
  let n6 = n2.branch(b2, mclsNext)
  echo root.toDot
