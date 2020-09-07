type
  MCPlayerColor* = enum
    mccWhite, mccBlack

proc `$`*(c: MCPlayerColor): string =
  if c == mccWhite: "white" else: "black"

proc oppositeColor*(c: MCPlayerColor): MCPlayerColor =
  if c == mccWhite: return mccBlack
  else: return mccWhite
