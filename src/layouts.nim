import latticenodes, boards
import tables, strformat

type
  MCLayoutPosition* = tuple[x: int, y: int]
  MCLatticeLayout* = object
    placement*: Table[MCLayoutPosition, MCLatticeNode[MCBoard]]
    topLeft*, bottomRight*: MCLayoutPosition
    rootNode*: MCLayoutPosition

  LayoutOverlapError* = object of ValueError

proc `+`*(p1, p2: MCLayoutPosition): MCLayoutPosition = (p1.x + p2.x, p1.y + p2.y)

proc dims*(layout: MCLatticeLayout): tuple[width: int, height: int] =
  (layout.bottomRight.x - layout.topLeft.x + 1,
   layout.bottomRight.y - layout.topLeft.y + 1)


proc transpose*(layout: var MCLatticeLayout, dp: MCLayoutPosition) =
  layout.topLeft = layout.topLeft + dp
  layout.bottomRight = layout.bottomRight + dp
  layout.rootNode = layout.rootNode + dp
  var newPlacement = initTable[MCLayoutPosition, MCLatticeNode[MCBoard]]()
  for pos, node in layout.placement:
    newPlacement[pos + dp] = node
  layout.placement = newPlacement


proc moveTopLeftTo*(layout: var MCLatticeLayout, newTopLeft: MCLayoutPosition) =
  layout.transpose( (newTopLeft.x - layout.topLeft.x,
                     newTopLeft.y - layout.topLeft.y) )

proc emptyLayout*(): MCLatticeLayout =
  result.placement = initTable[MCLayoutPosition, MCLatticeNode[MCBoard]]()
  result.topLeft = (0, 0)
  result.bottomRight = (0, 0)
  result.rootNode = (0, 0)

proc addLayout*(l1: var MCLatticeLayout, l2: MCLatticeLayout) =
  l1.topLeft = (min(l1.topLeft.x, l2.topLeft.x),
                min(l1.topLeft.y, l2.topLeft.y))

  l1.bottomRight = (max(l1.bottomRight.x, l2.bottomRight.x),
                    max(l1.bottomRight.y, l2.bottomRight.y))

  for pos, node in l2.placement:
    if pos in l1.placement:
      raise newException(LayoutOverlapError, fmt"layout overlap: {pos} already has a node: {node}")
    l1.placement[pos] = node

iterator getSiblingsInOrder(node: MCLatticeNode[MCBoard]): MCLatticeNode[MCBoard] =
  var conductor = node
  while not conductor.prevSibling.isNil():
    conductor = conductor.prevSibling
  while not conductor.isNil():
    yield conductor
    conductor = conductor.nextSibling

proc layout*(node: MCLatticeNode[MCBoard]): MCLatticeLayout =
  if len(node.future) == 0:
    result = emptyLayout()
    result.placement[(0, 0)] = node
    return

  let fnode = node.future[0]
  var curOffset: MCLayoutPosition = (1, 0)
  var rootNodeYCoord = 0
  for child in fnode.getSiblingsInOrder():
    if child.past != node:
      continue
    var clayout = child.layout()
    let (_, clh) = clayout.dims()

    clayout.moveTopLeftTo( (0, 0) )
    clayout.transpose(curOffset)
    result.addLayout(clayout)

    if child == fnode:
      rootNodeYCoord = clayout.rootNode.y

    curOffset = curOffset + (0, clh)
  result.rootNode = (0, rootNodeYCoord)
  result.placement[result.rootNode] = node

when isMainModule:
  import games, startpos, moverules
  import sequtils, random, times, os

  randomize()
  var numMoves = 100
  var g = initGame(mcStartPos5x5)
  while numMoves > 0:
    numMoves -= 1
    
    let moves = toSeq(g.rootNode.getAllLegalMoves())
    echo len(moves), " legal moves"
    if len(moves) == 0:
      break
    let move = sample(moves)
    discard g.makeMove(move)

  var conductor = g.rootNode
  while len(conductor.future) > 0:
    conductor = conductor.future[0]
  echo g.rootNode.toDot
  echo "f->f"
  echo g.rootNode.future[0].future[0].board

  let l = g.rootNode.layout()

  echo l
