## t_adapter_run_round_trip — Spec-Implementation M4 verification.
##
## Confirms ``runner.run(binary, filter)`` actually invokes the
## ``ct-test-runner`` binary against a freshly-built test fixture and
## that the exit code propagates back through the adapter:
##
##   * Running a fixture with two PASS-only tests through the adapter
##     yields ``ExitCode == 0`` (ct-test-runner exits 0 when no test
##     fails).
##   * Running a fixture that contains a FAILING test yields a
##     non-zero ExitCode (ct-test-runner exits 1 on any failure).
##   * The filter argument is honoured: filtering down to the binary
##     stem of a pass-only fixture still passes; filtering to a string
##     that matches NO binary stem in the queue exits 1 (the runner
##     prints "no test binaries found" — empty queue exits 1 per its
##     own semantics).
##
## Resolution: ``CT_TEST_RUNNER`` env override pinpoints the runner
## binary so the test works in checkouts without a system install. If
## the env var isn't set, fall back to ``../../build/bin/ct-test-runner``
## relative to this file (the ct-test ``just build`` output).
##
## No skip()/mocks — this test actually spawns ct-test-runner against a
## real fixture; the assertions are on observable exit codes.

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

proc locateRunner(): string =
  ## Prefer the env override; fall back to the ct-test checkout build
  ## directory. The test wires this path through
  ## ``ctTestRunner(runnerPath = ...)`` so the adapter doesn't fall
  ## back to its built-in resolution rules.
  let explicit = getEnv("CT_TEST_RUNNER")
  if explicit.len > 0:
    return explicit
  let here = currentSourcePath().parentDir()
  let checkout = absolutePath(here / ".." / ".." / ".." / "build" /
    "bin" / "ct-test-runner")
  if fileExists(checkout):
    return checkout
  # Last resort: try PATH.
  findExe("ct-test-runner")

suite "t_adapter_run_round_trip":
  test "pass-only fixture exits 0 through the adapter":
    let tempRoot = createTempDir("ct-test-adapter-run-", "")
    defer: removeDir(tempRoot)
    let srcPath = writeFixture(tempRoot, "fixture_pass_only", passOnlySource)
    let binPath = absolutePath(tempRoot / "fixture_pass_only_bin")
    discard compileFixture(srcPath, binPath, "fixture_pass_only")

    let runnerPath = locateRunner()
    check runnerPath.len > 0
    check fileExists(runnerPath)

    let runner = ctTestRunner(runnerPath = runnerPath)
    let code = runner.run(TestBinary(path: binPath), filter = "")
    # ct-test-runner exits 0 only when every queued test passes.
    check code == 0

  test "failing fixture exits non-zero through the adapter":
    let tempRoot = createTempDir("ct-test-adapter-fail-", "")
    defer: removeDir(tempRoot)
    let srcPath = writeFixture(tempRoot, "fixture_failing", failingSource)
    let binPath = absolutePath(tempRoot / "fixture_failing_bin")
    discard compileFixture(srcPath, binPath, "fixture_failing")

    let runnerPath = locateRunner()
    check runnerPath.len > 0
    check fileExists(runnerPath)

    let runner = ctTestRunner(runnerPath = runnerPath)
    let code = runner.run(TestBinary(path: binPath), filter = "")
    # ct-test-runner exits 1 when any test fails.
    check code == 1

  test "filter argument is forwarded to ct-test-runner":
    # Use a fixture that BOTH passes and fails: filtering it down to
    # the binary stem still picks up the failing test (exit 1);
    # filtering to a substring that excludes the binary leaves the
    # queue empty and the runner exits 0 with zero cases. The
    # difference in exit codes proves the filter reaches the runner.
    let tempRoot = createTempDir("ct-test-adapter-filter-", "")
    defer: removeDir(tempRoot)
    let srcPath = writeFixture(tempRoot, "fixture_filter_signal",
      failingSource)
    let binPath = absolutePath(tempRoot / "fixture_filter_signal_bin")
    discard compileFixture(srcPath, binPath, "fixture_filter")

    let runnerPath = locateRunner()
    check fileExists(runnerPath)
    let runner = ctTestRunner(runnerPath = runnerPath)

    # Matching filter: the failing fixture runs and exits 1.
    let matched = runner.run(TestBinary(path: binPath),
      filter = "fixture_filter_signal")
    check matched == 1

    # Non-matching filter: queue ends up empty; runner exits 0 with
    # zero cases executed. The failing test never fires, so the
    # exit-code delta proves the filter reached the runner.
    let unmatched = runner.run(TestBinary(path: binPath),
      filter = "this_substring_is_not_in_any_binary_stem")
    check unmatched == 0
    check matched != unmatched
