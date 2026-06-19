## t_adapter_framework_dispatch — framework indication + per-protocol dispatch.
##
## Confirms:
##   * ``testBinary(path, framework)`` tags the binary and ``frameworkOf``
##     recovers it; empty/unknown tags fall back to ``DefaultFramework``.
##   * ``ctTestRunner`` dispatches RUN to the protocol the tag selects: the
##     same binary + same filter yields a different argv (and a different
##     exit code) under ``tfDirect`` (filter as a positional argument) vs
##     ``tfCtTestParallel`` (filter as ``--run <name>``), proving the
##     framework indicator routes execution.
##   * LIST / ENUMERATE for a ``tfDirect`` binary synthesise the basename.
##
## No skip()/mocks: it compiles a real probe binary and runs it.

import std/[os, osproc, strutils, tempfiles]
import std/unittest

import ct_test_runner_adapter

# A plain executable (NOT a ct_test_unittest_parallel binary): it inspects
# its own argv and exits 1 iff its FIRST positional argument is "fail".
const directProbeSource = """
import std/os
let args = commandLineParams()
if args.len > 0 and args[0] == "fail":
  quit(1)
quit(0)
"""

proc compileProbe(dir: string): string =
  let src = dir / "direct_probe.nim"
  writeFile(src, directProbeSource)
  let binOut = absolutePath(dir / "direct_probe_bin")
  let cmd = "nim c --hints:off --warnings:off --nimcache:" &
    (dir / "nc").quoteShell() & " --out:" & binOut.quoteShell() &
    " " & src.quoteShell()
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    echo output
    raise newException(IOError, "failed to compile direct probe: " & cmd)
  binOut

suite "framework indication":
  test "testBinary tags and frameworkOf recovers it":
    check testBinary("/x", tfDirect).metadata == "direct"
    check testBinary("/x", tfCtTestParallel).metadata == "ct-test-parallel"
    check frameworkOf(testBinary("/x", tfDirect)) == tfDirect
    check frameworkOf(testBinary("/x", tfCtTestParallel)) == tfCtTestParallel

  test "empty / unrecognised metadata falls back to the default framework":
    check frameworkOf(TestBinary(path: "/x", metadata: "")) == DefaultFramework
    check frameworkOf(TestBinary(path: "/x", metadata: "bogus")) == DefaultFramework
    check DefaultFramework == tfCtTestParallel

suite "framework dispatch routes RUN":
  test "the same filter takes different protocols under different frameworks":
    let tempRoot = createTempDir("ct-test-fw-", "")
    defer: removeDir(tempRoot)
    let binPath = compileProbe(tempRoot)
    let runner = ctTestRunner()

    # tfDirect: filter "fail" is a POSITIONAL arg -> probe sees
    # args[0] == "fail" -> exit 1.
    let directFail = runner.run(testBinary(binPath, tfDirect), filter = "fail")
    check directFail == 1
    # tfDirect, no filter / a non-"fail" positional -> exit 0.
    check runner.run(testBinary(binPath, tfDirect), filter = "") == 0
    check runner.run(testBinary(binPath, tfDirect), filter = "ok") == 0

    # tfCtTestParallel: filter "fail" becomes ``--run fail`` -> the probe's
    # first arg is "--run", not "fail" -> exit 0. Same binary + same
    # filter, different protocol => different exit code, proving dispatch.
    let parallelFail =
      runner.run(testBinary(binPath, tfCtTestParallel), filter = "fail")
    check parallelFail == 0
    check directFail != parallelFail

suite "direct framework LIST/ENUMERATE":
  test "synthesise the binary basename":
    let runner = ctTestRunner()
    let b = testBinary("/tmp/some" / "probe_bin", tfDirect)
    let listed = runner.list(b)
    check listed.len == 1
    check listed[0].qualifiedName == "probe_bin"
    check runner.enumerate(b) == @["probe_bin"]
