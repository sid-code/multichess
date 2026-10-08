type
  MCPlayerColor* = enum
    mccWhite, mccBlack

proc oppositeColor*(c: MCPlayerColor): MCPlayerColor =
  if c == mccWhite: return mccBlack
  else: return mccWhite
