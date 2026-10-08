
type
  MCPiece* = enum
    mcpNone = 0, mcpPawn, mcpKnight, mcpBishop, mcpRook, mcpQueen, mcpKing

const mcPieces* = mcpPawn..mcpKing
