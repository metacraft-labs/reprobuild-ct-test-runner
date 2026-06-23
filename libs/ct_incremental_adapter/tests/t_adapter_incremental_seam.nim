## t_adapter_incremental_seam — the M0b-1 seam test.
##
## Proves that ``watchTestEdgeDecision`` exposed by ``ct_incremental_adapter``
## returns the SAME skip/re-run verdict that codetracer's canonical engine
## (`decide`) makes — i.e. the adapter is thin GLUE over codetracer's engine,
## not a reimplementation:
##
##   * an UNCHANGED test edge ⇒ ``weaSkip`` (``reason == "unchanged"``), the
##     translation of the engine's ``idSkipUnchanged``;
##   * editing an EXECUTED function ⇒ ``weaRun`` NAMING the changed function in
##     ``changedFuncs``, the translation of the engine's ``idRerunChanged``;
##   * editing a NON-executed function ⇒ ``weaSkip`` (the executed set is
##     unaffected);
##   * an unknown test edge ⇒ ``weaRun`` (``reason == "fresh"``), the engine's
##     ``idRunFresh``;
##   * a missing/unreadable cache file ⇒ ``weaRun`` fail-safe — never a silent
##     skip.
##
## To PROVE it is codetracer's engine deciding (not a constant), each case is
## also cross-checked against the engine's own ``decide`` over the SAME on-disk
## cache + source tree: the adapter's ``WatchEdgeAction`` must agree with the
## engine's ``IncrementalDecisionKind`` on every case.
##
## The seam loads the cache FROM DISK (``loadCache``), so the test drives the
## full canonical path: ``initCache`` + engine ``record`` + ``saveCache`` to
## materialize the cache, then ``watchTestEdgeDecision`` to read it back and
## decide. The cache is the only carrier between record and decide.
##
## Fixture: codetracer's committed ``m0_three_funcs`` Ruby trace + source
## (the same fixture the engine's own M0 parity test uses), resolved via the
## same sibling/env wiring as ``config.nims``.

import std/[unittest, os, strutils, times]

import ct_incremental_adapter
  # exposes watchTestEdgeDecision + WatchEdgeDecision/weaSkip/weaRun, AND
  # re-exports codetracer's engine (initCache/record/saveCache/decide/…).

# ---------------------------------------------------------------------------
# Locate codetracer's committed m0_three_funcs fixture (engine-side).
# Resolution MIRRORS config.nims: CODETRACER_CT_TEST_SRC env, else the sibling
# checkout next to this repo.
# ---------------------------------------------------------------------------

proc ctTestSrcDir(): string =
  let env = getEnv("CODETRACER_CT_TEST_SRC")
  if env.len > 0:
    return env
  # tests/<this file> -> ct_incremental_adapter -> libs -> repo root -> ws root
  let repoRoot = currentSourcePath().parentDir.parentDir.parentDir.parentDir
  repoRoot.parentDir / "codetracer" / "src" / "ct_test"

let
  fixturesDir = ctTestSrcDir() / "incremental" / "fixtures"
  threeFuncsFixture = fixturesDir / "m0_three_funcs"
  threeFuncsTrace = threeFuncsFixture / "trace"
  # The trace records the source path as
  # `/fixtures/m0_three_funcs/src/three_funcs.rb`; the engine strips the leading
  # slash and resolves it under `sourceRoot`, so the temp source must live at
  # `<sourceRoot>/fixtures/m0_three_funcs/src/three_funcs.rb`.
  relSourcePath = "fixtures/m0_three_funcs/src/three_funcs.rb"
  sourceTestId = "fixture::three_funcs"

# Fail loudly (not skip) if the codetracer sibling is absent — the build itself
# would already have failed to import the engine, but a clear runtime message
# pinpoints the missing fixture if only the fixtures are absent.
doAssert dirExists(threeFuncsTrace),
  "codetracer m0_three_funcs trace fixture not found at " & threeFuncsTrace &
  " (set CODETRACER_CT_TEST_SRC or check out the codetracer sibling)"

var counter = 0

proc makeSourceRoot(): string =
  ## Fresh temp dir with the fixture source copied to the path the trace expects.
  inc counter
  let stamp = (epochTime() * 1_000_000.0).int64
  let root = getTempDir() / ("ct_seam_src_" & $stamp & "_" & $counter)
  let dst = root / relSourcePath
  createDir(dst.parentDir)
  copyFile(threeFuncsFixture / "src" / "three_funcs.rb", dst)
  root

proc editFunctionBody(root, funcName, newBody: string) =
  let path = root / relSourcePath
  var lines = readFile(path).split('\n')
  for i in 0 ..< lines.len:
    if lines[i].strip() == "def " & funcName:
      doAssert i + 1 < lines.len
      lines[i + 1] = "  " & newBody
      writeFile(path, lines.join("\n"))
      return
  doAssert false, "function not found: " & funcName

proc recordToDisk(root, cachePath: string) =
  ## Drive codetracer's CANONICAL engine to record a baseline cache to disk.
  ## This is the engine's `record` + `saveCache` — the same machinery
  ## `watchTestEdgeDecision`'s `loadCache` reads back.
  var cache = initCache(cachePath)
  check record(cache, sourceTestId, threeFuncsTrace, root).isOk
  check saveCache(cache).isOk

suite "M0b-1 — watchTestEdgeDecision seam backed by codetracer's engine":

  test "unchanged_source_skips (engine idSkipUnchanged -> weaSkip)":
    let root = makeSourceRoot()
    let cachePath = root / "cache.json"
    recordToDisk(root, cachePath)

    let d = watchTestEdgeDecision(sourceTestId, threeFuncsTrace, root, cachePath)
    check d.action == weaSkip
    check d.reason == "unchanged"
    check d.testId == sourceTestId

    # Prove it is codetracer's engine deciding: the engine's own `decide` over
    # the same on-disk cache must agree.
    let cache = loadCache(cachePath).value
    check decide(sourceTestId, threeFuncsTrace, root, cache).kind ==
      idSkipUnchanged

  test "changed_executed_function_reruns_naming_it (idRerunChanged -> weaRun)":
    let root = makeSourceRoot()
    let cachePath = root / "cache.json"
    recordToDisk(root, cachePath)
    editFunctionBody(root, "used_a", "42 + 1")

    let d = watchTestEdgeDecision(sourceTestId, threeFuncsTrace, root, cachePath)
    check d.action == weaRun
    check "used_a" in d.changedFuncs
    check d.reason.startsWith("changed:")
    check "used_a" in d.reason

    # Engine agreement: `decide` independently reports idRerunChanged naming
    # the same function.
    let cache = loadCache(cachePath).value
    let ed = decide(sourceTestId, threeFuncsTrace, root, cache)
    check ed.kind == idRerunChanged
    check "used_a" in ed.changedFuncs
    # The adapter faithfully forwards the engine's changed set verbatim.
    check d.changedFuncs == ed.changedFuncs

  test "changed_unexecuted_function_skips (executed set unaffected)":
    let root = makeSourceRoot()
    let cachePath = root / "cache.json"
    recordToDisk(root, cachePath)
    editFunctionBody(root, "unused_c", "999")

    let d = watchTestEdgeDecision(sourceTestId, threeFuncsTrace, root, cachePath)
    check d.action == weaSkip

    let cache = loadCache(cachePath).value
    check decide(sourceTestId, threeFuncsTrace, root, cache).kind ==
      idSkipUnchanged

  test "unknown_test_runs_fresh (idRunFresh -> weaRun)":
    let root = makeSourceRoot()
    let cachePath = root / "cache.json"
    recordToDisk(root, cachePath)

    let d = watchTestEdgeDecision("never::recorded", threeFuncsTrace, root,
                                  cachePath)
    check d.action == weaRun
    check d.reason == "fresh"

    let cache = loadCache(cachePath).value
    check decide("never::recorded", threeFuncsTrace, root, cache).kind ==
      idRunFresh

  test "missing_cache_file_is_fresh_run (engine fresh, never a silent skip)":
    # A non-existent cache path: codetracer's `loadCache` returns a FRESH empty
    # cache (Ok), so every test decides idRunFresh — a run, never a skip.
    let root = makeSourceRoot()
    let cachePath = root / "does-not-exist.json"
    let d = watchTestEdgeDecision(sourceTestId, threeFuncsTrace, root, cachePath)
    check d.action == weaRun
    check d.reason == "fresh"

  test "malformed_cache_file_is_failsafe_run (never a silent skip)":
    # A corrupt cache file: codetracer's `loadCache` returns Err, and the seam
    # MUST translate that to a fail-safe re-run — losing the cache can never
    # cause a test that should run to be skipped.
    let root = makeSourceRoot()
    let cachePath = root / "cache.json"
    writeFile(cachePath, "{ this is not valid json ")
    let d = watchTestEdgeDecision(sourceTestId, threeFuncsTrace, root, cachePath)
    check d.action == weaRun
    check d.reason.startsWith("error:")

  test "gate_disabled_short_circuits_to_run_without_touching_cache":
    # The legacy/no-flag path: the gate is disabled, so the seam returns a run
    # verdict WITHOUT consulting the engine (proving the no-flag path can never
    # skip). A bogus cache path is supplied to prove it is never read.
    let gate = WatchCtIncrementalGate(enabled: false)
    let d = gatedWatchDecision(gate, sourceTestId, threeFuncsTrace,
                               "/nonexistent", "/nonexistent/cache.json")
    check d.action == weaRun
    check d.reason == "ct-incremental-disabled"

  test "gate_enabled_delegates_to_seam (engine decides skip)":
    let root = makeSourceRoot()
    let cachePath = root / "cache.json"
    recordToDisk(root, cachePath)
    let gate = WatchCtIncrementalGate(enabled: true)
    let d = gatedWatchDecision(gate, sourceTestId, threeFuncsTrace, root,
                               cachePath)
    check d.action == weaSkip
    check d.reason == "unchanged"
