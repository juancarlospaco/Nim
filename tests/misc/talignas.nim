discard """
ccodeCheck: "\\i @'NIM_ALIGN(128) NI mylocal1' .*"
target: "c cpp"
output: "align ok"
"""

# This is for Azure. The keyword ``alignof`` only exists in ``c++11``
# and newer. On Azure gcc does not default to c++11 yet.
when defined(cpp) and not defined(windows):
  {.passC: "-std=c++11".}

import globalalignas

var toplevel1 {.align: 32.} : int32
var toplevel2 {.align: 32.} : int32
var toplevel3 {.align: 32.} : int32

proc foobar() =
  var myvar1 {.global, align(64).}: int = 123
  var myvar2 {.global, align(64).}: int = 123
  var myvar3 {.global, align(64).}: int = 123

  doAssert (cast[uint](addr(myglobal1)) and 127) == 0
  doAssert (cast[uint](addr(myglobal2)) and 127) == 0
  doAssert (cast[uint](addr(myglobal3)) and 127) == 0

  doAssert (cast[uint](addr(myvar1)) and 63) == 0
  doAssert (cast[uint](addr(myvar2)) and 63) == 0
  doAssert (cast[uint](addr(myvar3)) and 63) == 0

  doAssert (cast[uint](addr(toplevel1)) and 31) == 0
  doAssert (cast[uint](addr(toplevel2)) and 31) == 0
  doAssert (cast[uint](addr(toplevel3)) and 31) == 0

  # test multiple align expressions
  var mylocal1 {.align(0), align(128), align(32).}: int = 123
  var mylocal2 {.align(128), align(0), align(32).}: int = 123
  var mylocal3 {.align(0), align(32), align(128).}: int = 123

  doAssert (cast[uint](addr(mylocal1)) and 127) == 0
  doAssert (cast[uint](addr(mylocal2)) and 127) == 0
  doAssert (cast[uint](addr(mylocal3)) and 127) == 0

  echo "align ok"

foobar()
