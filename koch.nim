#
#
#         Maintenance program for Nim
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
#    See doc/koch.txt for documentation.
#

const
  NimbleStableCommit = "8f7af860c5ce9634af880a7081c6435e1f2a5148" # master
  FusionStableCommit = "319aac4d43b04113831b529f8003e82f4af6a4a5"

when not defined(windows):
  const
    Z3StableCommit = "65de3f748a6812eecd7db7c478d5fc54424d368b" # the version of Z3 that DrNim uses

when defined(gcc) and defined(windows):
  when defined(x86):
    {.link: "icons/koch.res".}
  else:
    {.link: "icons/koch_icon.o".}

when defined(amd64) and defined(windows) and defined(vcc):
  {.link: "icons/koch-amd64-windows-vcc.res".}
when defined(i386) and defined(windows) and defined(vcc):
  {.link: "icons/koch-i386-windows-vcc.res".}

import std/[os, strutils, parseopt, osproc]
  # Using `std/os` instead of `os` to fail early if config isn't set up properly.
  # If this fails with: `Error: cannot open file: std/os`, see
  # https://github.com/nim-lang/Nim/pull/14291 for explanation + how to fix.

import tools / kochdocs
import tools / deps

const VersionAsString = system.NimVersion

const
  HelpText = """
+-----------------------------------------------------------------+
|         Maintenance program for Nim                             |
|             Version $1|
|             (c) 2017 Andreas Rumpf                              |
+-----------------------------------------------------------------+
Build time: $2, $3

Usage:
  koch [options] command [options for command]
Options:
  --help, -h               shows this help and quits
  --latest                 bundle the installers with bleeding edge versions of
                           external components.
  --stable                 bundle the installers with stable versions of
                           external components (default).
  --nim:path               use specified path for nim binary
  --localdocs[:path]       only build local documentations. If a path is not
                           specified (or empty), the default is used.
Possible Commands:
  boot [options]           bootstraps with given command line options
  distrohelper [bindir]    helper for distro packagers
  tools                    builds Nim related tools
  toolsNoExternal          builds Nim related tools (except external tools,
                           e.g. nimble)
                           doesn't require network connectivity
  nimble                   builds the Nimble tool
  fusion                   clone fusion into the working tree
Boot options:
  -d:release               produce a release version of the compiler
  -d:nimUseLinenoise       use the linenoise library for interactive mode
                           `nim secret` (not needed on Windows)
  -d:leanCompiler          produce a compiler without JS codegen or
                           documentation generator in order to use less RAM
                           for bootstrapping

Commands for core developers:
  runCI                    runs continuous integration (CI), e.g. from travis
  docs [options]           generates the full documentation
  csource -d:danger        builds the C sources for installation
  pdf                      builds the PDF documentation
  zip                      builds the installation zip package
  xz                       builds the installation tar.xz package
  testinstall              test tar.xz package; Unix only!
  installdeps [options]    installs external dependency (e.g. tinyc) to dist/
  tests [options]          run the testsuite (run a subset of tests by
                           specifying a category, e.g. `tests cat async`)
  temp options             creates a temporary compiler for testing
  pushcsource              push generated C sources to its repo
Web options:
  --googleAnalytics:UA-... add the given google analytics code to the docs. To
                           build the official docs, use UA-48159761-1
"""

let kochExe* = when isMainModule: os.getAppFilename() # always correct when koch is main program, even if `koch` exe renamed e.g.: `nim c -o:koch_debug koch.nim`
               else: getAppDir() / "koch".exe # works for winrelease

proc kochExec*(cmd: string) =
  exec kochExe.quoteShell & " " & cmd

proc kochExecFold*(desc, cmd: string) =
  execFold(desc, kochExe.quoteShell & " " & cmd)

template withDir(dir, body) =
  let old = getCurrentDir()
  try:
    setCurrentDir(dir)
    body
  finally:
    setCurrentDir(old)

let origDir = getCurrentDir()
setCurrentDir(getAppDir())

proc tryExec(cmd: string): bool =
  echo(cmd)
  result = execShellCmd(cmd) == 0

proc safeRemove(filename: string) =
  if fileExists(filename): removeFile(filename)

proc overwriteFile(source, dest: string) =
  safeRemove(dest)
  moveFile(source, dest)

proc copyExe(source, dest: string) =
  safeRemove(dest)
  copyFile(dest=dest, source=source)
  inclFilePermissions(dest, {fpUserExec, fpGroupExec, fpOthersExec})

const
  compileNimInst = "tools/niminst/niminst"
  distDir = "dist"

proc csource(args: string) =
  nimexec(("cc $1 -r $3 --var:version=$2 --var:mingw=none csource " &
           "--main:compiler/nim.nim compiler/installer.ini $1") %
       [args, VersionAsString, compileNimInst])

proc bundleC2nim(args: string) =
  cloneDependency(distDir, "https://github.com/nim-lang/c2nim.git")
  nimCompile("dist/c2nim/c2nim",
             options = "--noNimblePath --path:. " & args)

proc bundleNimbleExe(latest: bool, args: string) =
  let commit = if latest: "HEAD" else: NimbleStableCommit
  cloneDependency(distDir, "https://github.com/nim-lang/nimble.git",
                  commit = commit, allowBundled = true)
  # installer.ini expects it under $nim/bin
  nimCompile("dist/nimble/src/nimble.nim",
             options = "-d:release --noNimblePath " & args)

proc bundleNimsuggest(args: string) =
  nimCompileFold("Compile nimsuggest", "nimsuggest/nimsuggest.nim",
                 options = "-d:release -d:danger " & args)

proc buildVccTool(args: string) =
  nimCompileFold("Compile Vcc", "tools/vccexe/vccexe.nim ", options = args)

proc bundleNimpretty(args: string) =
  nimCompileFold("Compile nimpretty", "nimpretty/nimpretty.nim",
                 options = "-d:release " & args)

proc bundleWinTools(args: string) =
  nimCompile("tools/finish.nim", outputDir = "", options = args)

  buildVccTool(args)
  nimCompile("tools/nimgrab.nim", options = "-d:ssl " & args)
  nimCompile("tools/nimgrep.nim", options = args)
  nimCompile("testament/testament.nim", options = args)
  when false:
    # not yet a tool worth including
    nimCompile(r"tools\downloader.nim",
               options = r"--cc:vcc --app:gui -d:ssl --noNimblePath --path:..\ui " & args)

proc bundleFusion(latest: bool) =
  let commit = if latest: "HEAD" else: FusionStableCommit
  cloneDependency(distDir, "https://github.com/nim-lang/fusion.git", commit,
                  allowBundled = true)
  copyDir(distDir / "fusion" / "src" / "fusion", "lib" / "fusion")

proc zip(latest: bool; args: string) =
  bundleFusion(latest)
  bundleNimbleExe(latest, args)
  bundleNimsuggest(args)
  bundleNimpretty(args)
  bundleWinTools(args)
  nimexec("cc -r $2 --var:version=$1 --var:mingw=none --main:compiler/nim.nim scripts compiler/installer.ini" %
       [VersionAsString, compileNimInst])
  exec("$# --var:version=$# --var:mingw=none --main:compiler/nim.nim zip compiler/installer.ini" %
       ["tools/niminst/niminst".exe, VersionAsString])

proc ensureCleanGit() =
  let (outp, status) = osproc.execCmdEx("git diff")
  if outp.len != 0:
    quit "Not a clean git repository; 'git diff' not empty!"
  if status != 0:
    quit "Not a clean git repository; 'git diff' returned non-zero!"

proc xz(latest: bool; args: string) =
  ensureCleanGit()
  nimexec("cc -r $2 --var:version=$1 --var:mingw=none --main:compiler/nim.nim scripts compiler/installer.ini" %
       [VersionAsString, compileNimInst])
  exec("$# --var:version=$# --var:mingw=none --main:compiler/nim.nim xz compiler/installer.ini" %
       ["tools" / "niminst" / "niminst".exe, VersionAsString])

proc buildTool(toolname, args: string) =
  nimexec("cc $# $#" % [args, toolname])
  copyFile(dest="bin" / splitFile(toolname).name.exe, source=toolname.exe)

proc buildTools(args: string = "") =
  bundleNimsuggest(args)
  nimCompileFold("Compile nimgrep", "tools/nimgrep.nim",
                 options = "-d:release " & args)
  when defined(windows): buildVccTool(args)
  bundleNimpretty(args)
  nimCompileFold("Compile nimfind", "tools/nimfind.nim",
                 options = "-d:release " & args)
  nimCompileFold("Compile testament", "testament/testament.nim",
                 options = "-d:release " & args)

proc nsis(latest: bool; args: string) =
  bundleFusion(latest)
  bundleNimbleExe(latest, args)
  bundleNimsuggest(args)
  bundleWinTools(args)
  # make sure we have generated the niminst executables:
  buildTool("tools/niminst/niminst", args)
  #buildTool("tools/nimgrep", args)
  # produce 'nim_debug.exe':
  #exec "nim c compiler" / "nim.nim"
  #copyExe("compiler/nim".exe, "bin/nim_debug".exe)
  exec(("tools" / "niminst" / "niminst --var:version=$# --var:mingw=mingw$#" &
        " nsis compiler/installer.ini") % [VersionAsString, $(sizeof(pointer)*8)])

proc geninstall(args="") =
  nimexec("cc -r $# --var:version=$# --var:mingw=none --main:compiler/nim.nim scripts compiler/installer.ini $#" %
       [compileNimInst, VersionAsString, args])

proc install(args: string) =
  geninstall()
  exec("sh ./install.sh $#" % args)

when false:
  proc web(args: string) =
    nimexec("js tools/dochack/dochack.nim")
    nimexec("cc -r tools/nimweb.nim $# web/website.ini --putenv:nimversion=$#" %
        [args, VersionAsString])

  proc website(args: string) =
    nimexec("cc -r tools/nimweb.nim $# --website web/website.ini --putenv:nimversion=$#" %
        [args, VersionAsString])

  proc pdf(args="") =
    exec("$# cc -r tools/nimweb.nim $# --pdf web/website.ini --putenv:nimversion=$#" %
        [findNim().quoteShell(), args, VersionAsString], additionalPATH=findNim().splitFile.dir)

# -------------- boot ---------------------------------------------------------

proc findStartNim: string =
  # we try several things before giving up:
  # * nimExe
  # * bin/nim
  # * $PATH/nim
  # If these fail, we try to build nim with the "build.(sh|bat)" script.
  let (nim, ok) = findNimImpl()
  if ok: return nim
  when defined(Posix):
    const buildScript = "build.sh"
    if fileExists(buildScript):
      if tryExec("./" & buildScript): return "bin" / nim
  else:
    const buildScript = "build.bat"
    if fileExists(buildScript):
      if tryExec(buildScript): return "bin" / nim

  echo("Found no nim compiler and every attempt to build one failed!")
  quit("FAILURE")

proc thVersion(i: int): string =
  result = ("compiler" / "nim" & $i).exe

template doUseCpp(): bool = getEnv("NIM_COMPILE_TO_CPP", "false") == "true"

proc boot(args: string) =
  var output = "compiler" / "nim".exe
  var finalDest = "bin" / "nim".exe
  # default to use the 'c' command:
  let useCpp = doUseCpp()
  let smartNimcache = (if "release" in args or "danger" in args: "nimcache/r_" else: "nimcache/d_") &
                      hostOS & "_" & hostCPU

  let nimStart = findStartNim().quoteShell()
  for i in 0..2:
    # Nim versions < (1, 1) expect Nim's exception type to have a 'raiseId' field for
    # C++ interop. Later Nim versions do this differently and removed the 'raiseId' field.
    # Thus we always bootstrap the first iteration with "c" and not with "cpp" as
    # a workaround.
    let defaultCommand = if useCpp and i > 0: "cpp" else: "c"
    let bootOptions = if args.len == 0 or args.startsWith("-"): defaultCommand else: ""
    echo "iteration: ", i+1
    var extraOption = ""
    var nimi = i.thVersion
    if i == 0:
      nimi = nimStart
      extraOption.add " --skipUserCfg --skipParentCfg"
        # The configs are skipped for bootstrap
        # (1st iteration) to prevent newer flags from breaking bootstrap phase.
      let ret = execCmdEx(nimStart & " --version")
      doAssert ret.exitCode == 0
      let version = ret.output.splitLines[0]
      # remove these when csources get updated
      template addLib() =
        extraOption.add " --lib:lib" # see https://github.com/nim-lang/Nim/pull/14291
      if version.startsWith "Nim Compiler Version 0.19.0":
        extraOption.add " -d:nimBoostrapCsources0_19_0"
        addLib()
      elif version.startsWith "Nim Compiler Version 0.20.0": addLib()

    # in order to use less memory, we split the build into two steps:
    # --compileOnly produces a $project.json file and does not run GCC/Clang.
    # jsonbuild then uses the $project.json file to build the Nim binary.
    exec "$# $# $# --nimcache:$# $# --compileOnly compiler" / "nim.nim" %
      [nimi, bootOptions, extraOption, smartNimcache, args]
    exec "$# jsonscript --nimcache:$# $# compiler" / "nim.nim" %
      [nimi, smartNimcache, args]

    if not fileExists(output):
      echo "[Warning] Executable file not found " & output
    if not fileExists(output):
      echo "[Warning] Executable file not found " & i.thVersion
    if sameFileContent(output, i.thVersion):
      echo "Executables are equal: SUCCESS!"
      copyExe(output, finalDest)
      return
    copyExe(output, (i+1).thVersion)
  copyExe(output, finalDest)
  when not defined(windows): echo "[Warning] executables are still not equal"

# -------------- clean --------------------------------------------------------

const
  cleanExt = [
    ".ppu", ".o", ".obj", ".dcu", ".~pas", ".~inc", ".~dsk", ".~dpr",
    ".map", ".tds", ".err", ".bak", ".pyc", ".exe", ".rod", ".pdb", ".idb",
    ".idx", ".ilk"
  ]
  ignore = [
    ".bzrignore", "nim", "nim.exe", "koch", "koch.exe", ".gitignore"
  ]

proc cleanAux(dir: string) =
  for kind, path in walkDir(dir):
    case kind
    of pcFile:
      var (_, name, ext) = splitFile(path)
      if ext == "" or cleanExt.contains(ext):
        if not ignore.contains(name):
          echo "removing: ", path
          removeFile(path)
    of pcDir:
      case splitPath(path).tail
      of "nimcache":
        echo "removing dir: ", path
        removeDir(path)
      of "dist", ".git", "icons": discard
      else: cleanAux(path)
    else: discard

proc removePattern(pattern: string) =
  for f in walkFiles(pattern):
    echo "removing: ", f
    removeFile(f)

proc clean(args: string) =
  removePattern("web/*.html")
  removePattern("doc/*.html")
  cleanAux(getCurrentDir())
  for kind, path in walkDir(getCurrentDir() / "build"):
    if kind == pcDir:
      echo "removing dir: ", path
      removeDir(path)

# -------------- builds a release ---------------------------------------------

proc winReleaseArch(arch: string) =
  doAssert arch in ["32", "64"]
  let cpu = if arch == "32": "i386" else: "amd64"

  template withMingw(path, body) =
    let prevPath = getEnv("PATH")
    putEnv("PATH", (if path.len > 0: path & PathSep else: "") & prevPath)
    try:
      body
    finally:
      putEnv("PATH", prevPath)

  withMingw r"..\mingw" & arch & r"\bin":
    # Rebuilding koch is necessary because it uses its pointer size to
    # determine which mingw link to put in the NSIS installer.
    inFold "winrelease koch":
      nimexec "c --cpu:$# koch" % cpu
    kochExecFold("winrelease boot", "boot -d:release --cpu:$#" % cpu)
    kochExecFold("winrelease zip", "zip -d:release")
    overwriteFile r"build\nim-$#.zip" % VersionAsString,
             r"web\upload\download\nim-$#_x$#.zip" % [VersionAsString, arch]

proc winRelease*() =
  # Now used from "tools/winrelease" and not directly supported by koch
  # anymore!
  # Build -docs file:
  when true:
    inFold "winrelease buildDocs":
      buildDocs(gaCode)
    withDir "web/upload/" & VersionAsString:
      inFold "winrelease zipdocs":
        exec "7z a -tzip docs-$#.zip *.html" % VersionAsString
    overwriteFile "web/upload/$1/docs-$1.zip" % VersionAsString,
                  "web/upload/download/docs-$1.zip" % VersionAsString
  when true:
    inFold "winrelease csource":
      csource("-d:danger")
  when sizeof(pointer) == 4:
    winReleaseArch "32"
  when sizeof(pointer) == 8:
    winReleaseArch "64"

# -------------- tests --------------------------------------------------------

template `|`(a, b): string = (if a.len > 0: a else: b)

proc tests(args: string) =
  nimexec "cc --opt:speed testament/testament"
  var testCmd = quoteShell(getCurrentDir() / "testament/testament".exe)
  testCmd.add " " & quoteShell("--nim:" & findNim())
  testCmd.add " " & (args|"all")
  let success = tryExec testCmd
  if not success:
    quit("tests failed", QuitFailure)

proc temp(args: string) =
  proc splitArgs(a: string): (string, string) =
    # every --options before the command (indicated by starting
    # with not a dash) is part of the bootArgs, the rest is part
    # of the programArgs:
    let args = os.parseCmdLine a
    result = ("", "")
    var i = 0
    while i < args.len and args[i][0] == '-':
      result[0].add " " & quoteShell(args[i])
      inc i
    while i < args.len:
      result[1].add " " & quoteShell(args[i])
      inc i

  let d = getAppDir()
  var output = d / "compiler" / "nim".exe
  var finalDest = d / "bin" / "nim_temp".exe
  # 125 is the magic number to tell git bisect to skip the current commit.
  var (bootArgs, programArgs) = splitArgs(args)
  if "doc" notin programArgs and
      "threads" notin programArgs and
      "js" notin programArgs and "rst2html" notin programArgs:
    bootArgs.add " -d:leanCompiler"
  let nimexec = findNim().quoteShell()
  exec(nimexec & " c -d:debug --debugger:native -d:nimBetterRun " & bootArgs & " " & (d / "compiler" / "nim"), 125)
  copyExe(output, finalDest)
  setCurrentDir(origDir)
  if programArgs.len > 0: exec(finalDest & " " & programArgs)

proc xtemp(cmd: string) =
  let d = getAppDir()
  copyExe(d / "bin" / "nim".exe, d / "bin" / "nim_backup".exe)
  try:
    withDir(d):
      temp""
    copyExe(d / "bin" / "nim_temp".exe, d / "bin" / "nim".exe)
    exec(cmd)
  finally:
    copyExe(d / "bin" / "nim_backup".exe, d / "bin" / "nim".exe)

proc buildDrNim(args: string) =
  if not dirExists("dist/nimz3"):
    exec("git clone https://github.com/zevv/nimz3.git dist/nimz3")
  when defined(windows):
    if not dirExists("dist/dlls"):
      exec("git clone -q https://github.com/nim-lang/dlls.git dist/dlls")
    copyExe("dist/dlls/libz3.dll", "bin/libz3.dll")
    execFold("build drnim", "nim c -o:$1 $2 drnim/drnim" % ["bin/drnim".exe, args])
  else:
    if not dirExists("dist/z3"):
      exec("git clone -q https://github.com/Z3Prover/z3.git dist/z3")
      withDir("dist/z3"):
        exec("git fetch")
        exec("git checkout " & Z3StableCommit)
        createDir("build")
        withDir("build"):
          exec("""cmake -DZ3_BUILD_LIBZ3_SHARED=FALSE -G "Unix Makefiles" ../""")
          exec("make -j4")
    execFold("build drnim", "nim cpp --dynlibOverride=libz3 -o:$1 $2 drnim/drnim" % ["bin/drnim".exe, args])
  # always run the tests for now:
  exec("testament/testament".exe & " --nim:" & "drnim".exe & " pat drnim/tests")


proc hostInfo(): string =
  "hostOS: $1, hostCPU: $2, int: $3, float: $4, cpuEndian: $5, cwd: $6" %
    [hostOS, hostCPU, $int.sizeof, $float.sizeof, $cpuEndian, getCurrentDir()]

proc installDeps(dep: string, commit = "") =
  # the hashes/urls are version controlled here, so can be changed seamlessly
  # and tied to a nim release (mimicking git submodules)
  var commit = commit
  case dep
  of "tinyc":
    if commit.len == 0: commit = "916cc2f94818a8a382dd8d4b8420978816c1dfb3"
    cloneDependency(distDir, "https://github.com/timotheecour/nim-tinyc-archive", commit)
  else: doAssert false, "unsupported: " & dep
  # xxx: also add linenoise, niminst etc, refs https://github.com/nim-lang/RFCs/issues/206

proc runCI(cmd: string) =
  doAssert cmd.len == 0, cmd # avoid silently ignoring
  echo "runCI: ", cmd
  echo hostInfo()
  # boot without -d:nimHasLibFFI to make sure this still works
  kochExecFold("Boot in release mode", "boot -d:release")

  ## build nimble early on to enable remainder to depend on it if needed
  kochExecFold("Build Nimble", "nimble")

  if getEnv("NIM_TEST_PACKAGES", "0") == "1":
    execFold("Test selected Nimble packages (1)", "nim c -r testament/testament cat nimble-packages-1")
  elif getEnv("NIM_TEST_PACKAGES", "0") == "2":
    execFold("Test selected Nimble packages (2)", "nim c -r testament/testament cat nimble-packages-2")
  else:
    buildTools()

    ## run tests
    execFold("Test nimscript", "nim e tests/test_nimscript.nims")
    when defined(windows):
      # note: will be over-written below
      execFold("Compile tester", "nim c -d:nimCoroutines --os:genode -d:posix --compileOnly testament/testament")

    # main bottleneck here
    # xxx: even though this is the main bottlneck, we could use same code to batch the other tests
    #[
    BUG: with initOptParser, `--batch:'' all` interprets `all` as the argument of --batch
    ]#
    execFold("Run tester", "nim c -r -d:nimCoroutines testament/testament --pedantic --batch:$1 all -d:nimCoroutines" % ["NIM_TESTAMENT_BATCH".getEnv("_")])

    block CT_FFI:
      when defined(posix): # windows can be handled in future PR's
        execFold("nimble install -y libffi", "nimble install -y libffi")
        const nimFFI = "./bin/nim.ctffi"
        # no need to bootstrap with koch boot (would be slower)
        let backend = if doUseCpp(): "cpp" else: "c"
        execFold("build with -d:nimHasLibFFI", "nim $1 -d:release -d:nimHasLibFFI -o:$2 compiler/nim.nim" % [backend, nimFFI])
        execFold("test with -d:nimHasLibFFI", "$1 $2 -r testament/testament --nim:$1 r tests/misc/trunner.nim -d:nimTrunnerFfi" % [nimFFI, backend])

    execFold("Run nimdoc tests", "nim c -r nimdoc/tester")
    execFold("Run rst2html tests", "nim c -r nimdoc/rsttester")
    execFold("Run nimpretty tests", "nim c -r nimpretty/tester.nim")
    when defined(posix):
      execFold("Run nimsuggest tests", "nim c -r nimsuggest/tester")

proc pushCsources() =
  if not dirExists("../csources/.git"):
    quit "[Error] no csources git repository found"
  csource("-d:danger")
  let cwd = getCurrentDir()
  try:
    copyDir("build/c_code", "../csources/c_code")
    copyFile("build/build.sh", "../csources/build.sh")
    copyFile("build/build.bat", "../csources/build.bat")
    copyFile("build/build64.bat", "../csources/build64.bat")
    copyFile("build/makefile", "../csources/makefile")

    setCurrentDir("../csources")
    for kind, path in walkDir("c_code"):
      if kind == pcDir:
        exec("git add " & path / "*.c")
    exec("git commit -am \"updated csources to version " & NimVersion & "\"")
    exec("git push origin master")
    exec("git tag -am \"Version $1\" v$1" % NimVersion)
    exec("git push origin v$1" % NimVersion)
  finally:
    setCurrentDir(cwd)

proc testUnixInstall(cmdLineRest: string) =
  csource("-d:danger" & cmdLineRest)
  xz(false, cmdLineRest)
  let oldCurrentDir = getCurrentDir()
  try:
    let destDir = getTempDir()
    copyFile("build/nim-$1.tar.xz" % VersionAsString,
             destDir / "nim-$1.tar.xz" % VersionAsString)
    setCurrentDir(destDir)
    execCleanPath("tar -xJf nim-$1.tar.xz" % VersionAsString)
    setCurrentDir("nim-$1" % VersionAsString)
    execCleanPath("sh build.sh")
    # first test: try if './bin/nim --version' outputs something sane:
    let output = execProcess("./bin/nim --version").splitLines
    if output.len > 0 and output[0].contains(VersionAsString):
      echo "Version check: success"
      execCleanPath("./bin/nim c koch.nim")
      execCleanPath("./koch boot -d:release", destDir / "bin")
      # check the docs build:
      execCleanPath("./koch docs", destDir / "bin")
      # check nimble builds:
      execCleanPath("./koch tools")
      # check the tests work:
      putEnv("NIM_EXE_NOT_IN_PATH", "NOT_IN_PATH")
      execCleanPath("./koch tests --nim:./bin/nim cat megatest", destDir / "bin")
    else:
      echo "Version check: failure"
  finally:
    setCurrentDir oldCurrentDir

proc valgrind(cmd: string) =
  # somewhat hacky: '=' sign means "pass to valgrind" else "pass to Nim"
  let args = parseCmdLine(cmd)
  var nimcmd = ""
  var valcmd = ""
  for i, a in args:
    if i == args.len-1:
      # last element is the filename:
      valcmd.add ' '
      valcmd.add changeFileExt(a, ExeExt)
      nimcmd.add ' '
      nimcmd.add a
    elif '=' in a:
      valcmd.add ' '
      valcmd.add a
    else:
      nimcmd.add ' '
      nimcmd.add a
  exec("nim c" & nimcmd)
  let supp = getAppDir() / "tools" / "nimgrind.supp"
  exec("valgrind --suppressions=" & supp & valcmd)

proc showHelp() =
  quit(HelpText % [VersionAsString & spaces(44-len(VersionAsString)),
                   CompileDate, CompileTime], QuitSuccess)

when isMainModule:
  var op = initOptParser()
  var
    latest = false
    localDocsOnly = false
    localDocsOut = ""
  while true:
    op.next()
    case op.kind
    of cmdLongOption, cmdShortOption:
      case normalize(op.key)
      of "latest": latest = true
      of "stable": latest = false
      of "nim": nimExe = op.val.absolutePath # absolute so still works with changeDir
      of "localdocs":
        localDocsOnly = true
        if op.val.len > 0:
          localDocsOut = op.val.absolutePath
      else: showHelp()
    of cmdArgument:
      case normalize(op.key)
      of "boot": boot(op.cmdLineRest)
      of "clean": clean(op.cmdLineRest)
      of "doc", "docs": buildDocs(op.cmdLineRest, localDocsOnly, localDocsOut)
      of "doc0", "docs0":
        # undocumented command for Araq-the-merciful:
        buildDocs(op.cmdLineRest & gaCode)
      of "pdf": buildPdfDoc(op.cmdLineRest, "doc/pdf")
      of "csource", "csources": csource(op.cmdLineRest)
      of "zip": zip(latest, op.cmdLineRest)
      of "xz": xz(latest, op.cmdLineRest)
      of "nsis": nsis(latest, op.cmdLineRest)
      of "geninstall": geninstall(op.cmdLineRest)
      of "distrohelper": geninstall()
      of "install": install(op.cmdLineRest)
      of "testinstall": testUnixInstall(op.cmdLineRest)
      of "installdeps": installDeps(op.cmdLineRest)
      of "runci": runCI(op.cmdLineRest)
      of "test", "tests": tests(op.cmdLineRest)
      of "temp": temp(op.cmdLineRest)
      of "xtemp": xtemp(op.cmdLineRest)
      of "wintools": bundleWinTools(op.cmdLineRest)
      of "nimble": bundleNimbleExe(latest, op.cmdLineRest)
      of "nimsuggest": bundleNimsuggest(op.cmdLineRest)
      # toolsNoNimble is kept for backward compatibility with build scripts
      of "toolsnonimble", "toolsnoexternal":
        buildTools(op.cmdLineRest)
      of "tools":
        buildTools(op.cmdLineRest)
        bundleNimbleExe(latest, op.cmdLineRest)
        bundleFusion(latest)
      of "pushcsource", "pushcsources": pushCsources()
      of "valgrind": valgrind(op.cmdLineRest)
      of "c2nim": bundleC2nim(op.cmdLineRest)
      of "drnim": buildDrNim(op.cmdLineRest)
      of "fusion": bundleFusion(latest)
      else: showHelp()
      break
    of cmdEnd: break
