# Package

version       = "0.1.0"
author        = "Sidharth Kulkarni"
description   = "Chess with multiple timelines and time travel"
license       = "MIT"
srcDir        = "src"
binDir        = "web"
backend       = "js"
bin           = @["web.js"]

# Dependencies

requires "nim >= 1.3.5"
requires "karax"
requires "html5_canvas"
