## M2 verification: ``--list-json`` produces valid JSON with a
## non-empty ``tests`` array, each entry having ``name``, ``suite``,
## ``file``, ``line``.
##
## Strategy: build the fixture ``fixture_protocol_three_tests`` once
## (three tests across two suites), invoke it with ``--list-json``,
## parse the output as JSON, and assert against the expected shape.

import std/[json, os, osproc, strutils]
import std/unittest

const fixtureSource = currentSourcePath().parentDir() /
  "fixtures" / "fixture_protocol_three_tests.nim"

# Per-test-binary output tag so two DIFFERENT test binaries that both build
# ``fixture_protocol_three_tests`` (this test and
# ``t_test_binary_run_one_writes_result_file``) never share the same
# ``build/test-bin`` output path / nimcache when run in parallel — a shared
# path lets one binary's ``nim c`` clobber the other's freshly-linked binary
# mid-exec (observed as a one-shot exit 126 "Permission denied"). Stable
# within a single test process, so repeated ``buildFixture()`` calls in this
# test still reuse one path.
proc fixtureTag(): string =
  splitFile(getAppFilename()).name

proc nimcacheDir(): string =
  result = getEnv("CT_TEST_PARALLEL_NIMCACHE")
  if result.len == 0:
    result = "build" / "nimcache" / "ct_test_unittest_parallel" /
      ("fixture_protocol_three_tests_" & fixtureTag())

proc buildFixture(): string =
  let outputPath = "build" / "test-bin" /
    ("ct_test_unittest_parallel_fixture_three_tests_" & fixtureTag())
  createDir(outputPath.parentDir())
  createDir(nimcacheDir())
  let cmd = "nim c --hints:off --warnings:off --nimcache:" &
    nimcacheDir().quoteShell() & " --out:" & outputPath.quoteShell() &
    " " & fixtureSource.quoteShell()
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    echo output
    raise newException(IOError, "failed to build fixture: " & cmd)
  # Return an ABSOLUTE path so the invocation never cwd-relative-resolves the
  # freshly-linked binary.
  absolutePath(outputPath)

suite "t_every_test_binary_speaks_list_json_protocol":
  test "list_json_returns_valid_catalog":
    let binary = buildFixture()
    let (output, exitCode) = execCmdEx(binary.quoteShell() & " --list-json")
    check exitCode == 0
    var doc: JsonNode = nil
    try:
      doc = parseJson(output)
    except JsonParsingError:
      checkpoint "stdout was:"
      checkpoint output
      fail()
    if doc != nil:
      check doc.kind == JObject
      check doc.hasKey("tests")
      let tests = doc["tests"]
      check tests.kind == JArray
      check tests.len == 3
      var foundAdd, foundSub, foundSkip = false
      for t in tests:
        check t.hasKey("name")
        check t.hasKey("suite")
        check t.hasKey("file")
        check t.hasKey("line")
        check t["file"].getStr().endsWith("fixture_protocol_three_tests.nim")
        check t["line"].getInt() > 0
        case t["name"].getStr()
        of "arithmetic::addition":
          foundAdd = true
          check t["suite"].getStr() == "arithmetic"
        of "arithmetic::subtraction_fails":
          foundSub = true
          check t["suite"].getStr() == "arithmetic"
        of "markers::skipped":
          foundSkip = true
          check t["suite"].getStr() == "markers"
      check foundAdd
      check foundSub
      check foundSkip

  test "list_plain_returns_one_name_per_line":
    let binary = buildFixture()
    let (output, exitCode) = execCmdEx(binary.quoteShell() & " --list")
    check exitCode == 0
    let lines = output.strip().splitLines()
    check lines.len == 3
    check "arithmetic::addition" in lines
    check "arithmetic::subtraction_fails" in lines
    check "markers::skipped" in lines
