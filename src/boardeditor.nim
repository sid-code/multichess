include karax/prelude
import dom
from sugar import `=>`

import boards, startpos, pieces, playercolors
import piececlasses

type
  MCBoardEditor* = ref object
    board: MCBoard

    # just a fancy way of saying a piece and a color
    pieceToPlace: MCSquare

    finishedCallback: proc(board: MCBoard)
    
proc newBoardEditor*(b = initBlankBoard(5, 5), cb: proc(board: MCBoard)): MCBoardEditor =
  new result
  result.board = b
  result.finishedCallback = cb

proc clearBoard(be: MCBoardEditor) =
  be.board = initBlankBoard(be.board.numFiles, be.board.numRanks)
proc addRank(be: MCBoardEditor) =
  be.board = initBlankBoard(be.board.numFiles, be.board.numRanks + 1)
proc addFile(be: MCBoardEditor) =
  be.board = initBlankBoard(be.board.numFiles + 1, be.board.numRanks)
proc removeRank(be: MCBoardEditor) =
  if be.board.numRanks > 0:
    be.board = initBlankBoard(be.board.numFiles, be.board.numRanks - 1)
proc removeFile(be: MCBoardEditor) =
  if be.board.numFiles > 0:
    be.board = initBlankBoard(be.board.numFiles - 1, be.board.numRanks)

proc makeSetModeCallback(be: MCBoardEditor, pieceToPlace: MCSquare): proc() =
  return (proc () =
            be.pieceToPlace = pieceToPlace)
proc makeSetSquareCallback(be: MCBoardEditor): proc(ev: Event, n: VNode) =
  return (proc (ev: Event, n: VNode) =
            if ev.target.getAttribute("file").isNil: return
            let file = parseInt(ev.target.getAttribute("file"))
            let rank = parseInt(ev.target.getAttribute("rank"))
            be.board[file, rank] = if be.board[file, rank] == be.pieceToPlace:
                                     (mcpNone, mccWhite)
                                   else:
                                     be.pieceToPlace)
proc render*(be: MCBoardEditor): VNode =
  result = buildHtml(tdiv):
    tdiv(class="board-editor-container"):
      tdiv(class="board-editor-controls"):
        p:
          text "board size"
          br()
          text "files "
          button(onclick=() => be.addFile()): text "+"
          button(onclick=() => be.removeFile()): text "-"
          text " ranks "
          button(onclick=() => be.addRank()): text "+"
          button(onclick=() => be.removeRank()): text "-"
        p:
          button(onclick=() => be.clearBoard()): text "clear board"
        p:
          text "Select piece"
          br()
          for color in [mccBlack, mccWhite]:
            for piece in low(MCPiece)..high(MCPiece):
              var squareClass = "square piecetoplace-square"
              if be.pieceToPlace == (piece, color):
                squareClass &= " piecetoplace-selected"
              tdiv(class=squareClass):
                tdiv(class=getClassFor((piece, color)),
                     onclick=be.makeSetModeCallback((piece, color)))
            br()

      tdiv(class="board", onclick=be.makeSetSquareCallback()):
        for r in countdown(be.board.numRanks-1, 0):
          for f in countup(0, be.board.numFiles-1):
            let blackSquareClass = if (f + r) mod 2 == 0:
                                     kstring("square square-black")
                                   else:
                                     kstring("square square-white")
            tdiv(class=blackSquareClass):
              tdiv(class=getClassFor(be.board[f, r]),
                   file=kstring($f),
                   rank=kstring($r))
    
          br()

      form:
        input(`type`="radio", id="toplay-white", value="white", name="toplay",
              onclick=proc() = be.board.toplay = mccWhite)
        label(`for`="toplay-white"): text "white"
        input(`type`="radio", id="toplay-black", value="black", name="toplay",
              onclick=proc() = be.board.toplay = mccBlack)
        label(`for`="toplay-black"): text "black"
        text " to play"
      button(onclick=proc() = be.finishedCallback(be.board)):
        text "go!"
