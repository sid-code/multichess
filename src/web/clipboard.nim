import dom

proc copyToClipboard*(str: cstring) =
  let ed = document.createElement("textarea")
  ed.value = str
  document.body.appendChild(ed)
  ed.select()
  asm """
document.execCommand("copy")
"""
  document.body.removeChild(ed)
