## t_adapter_run_round_trip — in-process run verification.
##
## Confirms ``runner.run(binary, filter)`` runs the test binary
## **in-process** (as a direct child of this process) via the binary's
## own protocol — there is no longer a separate ``ct-test-runner``
## orchestrator executable to locate or spawn:
##
##   * A pass-only fixture, run with no filter, exits 0 — the binary runs
##     its whole suite and its native exit code is forwarded.
##   * A failing fixture, run with no filter, exits non-zero.
##   * A filter selects a single case through the binary's ``--run
##     "<suite>::<test>"`` protocol: filtering a mixed fixture to its
##     passing case exits 0 while filtering to its failing case exits
##     non-zero — the exit-code delta proves the filter reaches the
##     binary.
##
## No skip()/mocks — this compiles real fixtures and runs them through the
## adapter; the assertions are on observable exit codes.

import std/[os, osproc, strutils, tempfiles]
import std/unittest

import ct_test_runner_adapter

const ctTestParallelSrc = currentSourcePath().parentDir() /
  ".." / ".." / "ct_test_unittest_parallel" / "src"

const passOnlySource = """
import ct_test_unittest_parallel

suite "addition":
  test "two_plus_two":
    check 2 + 2 == 4

  test "one_plus_one":
    check 1 + 1 == 2
"""

const failingSource = """
import ct_test_unittest_parallel

suite "broken":
  test "fails_on_purpose":
    check 1 == 2
"""

const mixedSource = """
import ct_test_unittest_parallel

suite "mixed":
  test "passes":
    check 1 == 1

  test "fails":
    check 1 == 2
"""

proc nimcacheDir(label: string): string =
  result = getEnv("CT_TEST_ADAPTER_NIMCACHE_RUN")
  if result.len == 0:
    result = "build" / "nimcache" / "ct_test_runner_adapter" / label

proc writeFixture(dir, basename, source: string): string =
  let sourcePath = dir / basename & ".nim"
  writeFile(sourcePath, source)
  sourcePath

proc compileFixture(sourcePath: string;
                    binaryOut: string;
                    cacheLabel: string): string =
  ## Compile a source fixture into a test binary; returns the binary's
  ## absolute path. Failure to compile raises so the test fails loudly.
  createDir(binaryOut.parentDir())
  createDir(nimcacheDir(cacheLabel))
  let cmd = "nim c --hints:off --warnings:off --path:" &
    ctTestParallelSrc.quoteShell() & " --nimcache:" &
    nimcacheDir(cacheLabel).quoteShell() &
    " --out:" & binaryOut.quoteShell() & " " & sourcePath.quoteShell()
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    echo output
    raise newException(IOError,
      "failed to compile adapter run-roundtrip fixture: " & cmd)
  binaryOut

suite "t_adapter_run_round_trip":
  test "pass-only fixture exits 0 through the in-process adapter":
    let tempRoot = createTempDir("ct-test-adapter-run-", "")
    defer: removeDir(tempRoot)
    let srcPath = writeFixture(tempRoot, "fixture_pass_only", passOnlySource)
    let binPath = absolutePath(tempRoot / "fixture_pass_only_bin")
    discard compileFixture(srcPath, binPath, "fixture_pass_only")

    let runner = ctTestRunner()
    # The binary runs its whole suite (no filter) and forwards exit 0.
    check runner.run(TestBinary(path: binPath), filter = "") == 0

  test "failing fixture exits non-zero through the in-process adapter":
    let tempRoot = createTempDir("ct-test-adapter-fail-", "")
    defer: removeDir(tempRoot)
    let srcPath = writeFixture(tempRoot, "fixture_failing", failingSource)
    let binPath = absolutePath(tempRoot / "fixture_failing_bin")
    discard compileFixture(srcPath, binPath, "fixture_failing")

    let runner = ctTestRunner()
    check runner.run(TestBinary(path: binPath), filter = "") != 0

  test "filter selects a single case via the binary --run protocol":
    # A mixed fixture (one passing case, one failing) run with no filter
    # fails overall; filtering to the *passing* case exits 0 and to the
    # *failing* case exits non-zero. The delta proves the filter is
    # forwarded to the binary's --run protocol rather than ignored.
    let tempRoot = createTempDir("ct-test-adapter-filter-", "")
    defer: removeDir(tempRoot)
    let srcPath = writeFixture(tempRoot, "fixture_mixed", mixedSource)
    let binPath = absolutePath(tempRoot / "fixture_mixed_bin")
    discard compileFixture(srcPath, binPath, "fixture_mixed")

    let runner = ctTestRunner()

    # Resolve the binary's own qualified names so the filter matches the
    # exact ``<suite>::<test>`` strings the binary recognises.
    let names = runner.enumerate(TestBinary(path: binPath))
    check names.len == 2
    var passName, failName: string
    for n in names:
      if n.endsWith("passes"): passName = n
      elif n.endsWith("fails"): failName = n
    check passName.len > 0
    check failName.len > 0

    let passCode = runner.run(TestBinary(path: binPath), filter = passName)
    let failCode = runner.run(TestBinary(path: binPath), filter = failName)
    check passCode == 0
    check failCode != 0
    check passCode != failCode
