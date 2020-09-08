# Code to render a move log
include karax/prelude
import tables, strformat
import games, boards, moves, playercolors, positions

proc render(i: MCMoveInfo, onclickmove: proc(i: MCMoveInfo)): VNode =
  result = buildHtml(tdiv):
    let fp = i.move.fromPos
    let tp = i.move.toPos
    let sq = fp.getSquare()
    text fmt"{sq} ({fp.file}, {fp.rank}) -> ({tp.file}, {tp.rank})"
    proc onclick(ev: Event, n: VNode) =
      onclickmove(i)

proc renderMoveLog*(g: MCGame, onclickmove: proc(i: MCMoveInfo)): VNode =
  result = buildHtml(tdiv):
    for info in g.moveLog:
      render(info, onclickmove)
