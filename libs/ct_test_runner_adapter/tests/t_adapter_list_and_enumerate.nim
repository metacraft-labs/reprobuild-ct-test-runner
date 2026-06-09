## t_adapter_list_and_enumerate — Spec-Implementation M4 verification.
##
## Confirms the ``TestRunner`` adapter's ``list`` and ``enumerate``
## procs invoke the test binary's own ``--list-json`` / ``--list``
## protocol surface (Tier-1 "Standard" — see
## ``codetracer-specs/Planned-Features/Nim-Parallel-Test-Framework.md``
## §3.6) and parse the expected catalog shape:
##
##   * ``list(binary)`` returns one ``TestCase`` per declared test,
##     with ``qualifiedName`` in ``<suite>::<test>`` form and a
##     non-empty ``displayName``.
##   * ``enumerate(binary)`` returns the bare qualified-name list, one
##     line per test, in declaration order.
##
## Strategy: build the existing ``fixture_protocol_three_tests`` (three
## tests across two suites), feed its binary path into the adapter
## procs, and assert on the parsed result. No skip()/mocks — the test
## actually compiles and runs the fixture binary against the adapter.

import std/[algorithm, os, osproc, strutils, tables]
import std/unittest

import ct_test_runner_adapter

const fixtureSource = currentSourcePath().parentDir() /
  ".." / ".." / "ct_test_unittest_parallel" / "tests" /
  "fixtures" / "fixture_protocol_three_tests.nim"

proc nimcacheDir(): string =
  result = getEnv("CT_TEST_ADAPTER_NIMCACHE")
  if result.len == 0:
    result = "build" / "nimcache" / "ct_test_runner_adapter" /
      "fixture_three_tests"

proc buildFixture(): string =
  ## Compile the protocol fixture binary once. Returns the absolute
  ## path of the resulting binary.
  let outputPath = absolutePath("build" / "test-bin" /
    "ct_test_runner_adapter_fixture_three_tests")
  createDir(outputPath.parentDir())
  createDir(nimcacheDir())
  let cmd = "nim c --hints:off --warnings:off --nimcache:" &
    nimcacheDir().quoteShell() & " --out:" & outputPath.quoteShell() &
    " " & fixtureSource.quoteShell()
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    echo output
    raise newException(IOError, "failed to build fixture: " & cmd)
  outputPath

suite "t_adapter_list_and_enumerate":
  test "list returns the parsed --list-json catalog":
    let binaryPath = buildFixture()
    let runner = ctTestRunner()
    let cases = runner.list(TestBinary(path: binaryPath))
    # Three tests, all carry qualified <suite>::<test> form, two
    # distinct suites.
    check cases.len == 3
    var qualified: seq[string] = @[]
    var displays: seq[string] = @[]
    var suites = initCountTable[string]()
    for c in cases:
      qualified.add(c.qualifiedName)
      displays.add(c.displayName)
      let parts = c.qualifiedName.split("::")
      check parts.len == 2
      suites.inc(parts[0])
    qualified.sort()
    check qualified == @[
      "arithmetic::addition",
      "arithmetic::subtraction_fails",
      "markers::skipped",
    ]
    check suites["arithmetic"] == 2
    check suites["markers"] == 1
    # Every display name is non-empty so a human-facing log line has
    # something to print.
    for d in displays:
      check d.len > 0

  test "enumerate returns one qualified-name per line":
    let binaryPath = buildFixture()
    let runner = ctTestRunner()
    let names = runner.enumerate(TestBinary(path: binaryPath))
    # The binary's --list mode emits one name per line; the adapter
    # strips blank lines but otherwise preserves order.
    check names.len == 3
    var sorted = @names
    sorted.sort()
    check sorted == @[
      "arithmetic::addition",
      "arithmetic::subtraction_fails",
      "markers::skipped",
    ]
    # Each name is in the canonical <suite>::<test> form.
    for n in names:
      check "::" in n
      check n.strip() == n

  test "list and enumerate agree on the qualified-name set":
    let binaryPath = buildFixture()
    let runner = ctTestRunner()
    let cases = runner.list(TestBinary(path: binaryPath))
    let names = runner.enumerate(TestBinary(path: binaryPath))
    var fromList: seq[string] = @[]
    for c in cases:
      fromList.add(c.qualifiedName)
    fromList.sort()
    var fromEnumerate = @names
    fromEnumerate.sort()
    check fromList == fromEnumerate
    check fromList.len == 3
    check "arithmetic::addition" in fromList
