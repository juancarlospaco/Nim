#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This is an include file that simply imports common modules for your
# convenience:
#
# .. code-block:: nim
#   include prelude
#
# Same as:
#
# .. code-block:: nim
#   import os, strutils, times, parseutils, parseopt, hashes, tables, sets, math, sequtils

import os, strutils, times, parseutils, hashes, tables, sets, math, sequtils
when not defined(js): import parseopt
