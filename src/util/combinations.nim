import math
import bitops

## Iterator over all possible combinations of `arr` with size `size`.
## WARNING: This is exponential in the size of `arr`; Do not use with
## lists much larger than size 10.
iterator combinations*[T](arr: openArray[T], size = -1): seq[T] =
  for x in 0..2^arr.len-1:
    if size > -1 and popcount(x) != size:
      continue

    var y = x
    var i = 0

    var combo: seq[T]
    while y > 0:
      if bitand(y, 1) == 1:
        combo.add(arr[i])
      y = y shr 1
      i += 1
    yield combo

when isMainModule:
  for combo in combinations(@[1, 2, 3, 4, 5], 3):
    echo combo
