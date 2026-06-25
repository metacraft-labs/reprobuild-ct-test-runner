## ct_incremental_adapter — the watch-integration decision seam, backed by
## codetracer's CANONICAL incremental engine **invoked as a subprocess**.
##
## # Why this module exists
##
## `repro watch --ct-incremental` (wired in reprobuild's `repro_cli_support`)
## needs a single decision function it can call on every filesystem-change
## cycle: given a watched test edge, decide whether the test may be skipped
## because none of the functions it previously executed have changed, or must be
## re-run. Reprobuild calls
## ``watchTestEdgeDecision(testId, traceDir, sourceRoot, cachePath)`` and acts on
## the returned ``WatchEdgeDecision`` (``weaSkip`` / ``weaRun`` + ``reason`` +
## ``changedFuncs``); after a re-run it calls ``recordWatchTestEdge`` to refresh
## the cache.
##
## # Engine coupling: process boundary, not link boundary
##
## codetracer owns the incremental engine. Earlier this adapter ``import``ed
## codetracer's engine and ran the decision IN-PROCESS, which forced reprobuild's
## build to compile codetracer's whole engine (+ trace-format-nim + results +
## zstd). The canonical design keeps the dependency one-way AND out of
## reprobuild's compile: the engine ships as codetracer's ``ct`` binary, and this
## adapter EXECUTES it. So reprobuild compiles ONLY this thin adapter; the engine
## is a runtime process dependency resolved from ``$CT_BIN`` (CI sets it to the
## ``ct`` built in the codetracer sibling) or ``ct`` on ``PATH``.
##
## The ``ct`` granular protocol this adapter speaks (codetracer's
## ``src/ct_test/incremental_cli.nim``):
##   * ``ct test --incremental --watch-decide  --test-id .. --trace-dir .. \
##       --source-root .. --cache-path ..`` → one JSON line
##       ``{"status":"run"|"skip","reason":..,"changedFuncs":[..]}``
##   * ``ct test --incremental --watch-record  <same flags> [--non-deterministic]``
##       → one JSON line ``{"ok":bool,"error":str}``
##
## # Dependency direction (one-way)
##
## This adapter imports NOTHING from reprobuild and NOTHING from codetracer's
## engine sources — only std modules. The ``WatchEdgeDecision`` /
## ``WatchEdgeAction`` types are declared HERE (a value contract reprobuild binds
## against), so reprobuild's `repro_cli_support` call site is satisfied unchanged.
##
## # Fail-safe
##
## Any subprocess failure (missing ``ct``, non-zero exit, unparseable output) is
## reported as a conservative RE-RUN (``weaRun`` + ``error: ..``) — never a
## silent skip. Losing the engine must never cause a test that should run to be
## skipped.

import std/[os, osproc, strutils, json]

type
  WatchEdgeAction* = enum
    ## What the watch loop should do with the watched test edge this cycle.
    weaRun        ## Re-run the test edge (fresh, changed, or fail-safe error).
    weaSkip       ## Skip — no executed function changed since the last record.

  WatchEdgeDecision* = object
    ## The seam's verdict for one watched test edge on one change cycle.
    action*: WatchEdgeAction
    testId*: string
      ## The test edge's identity (echoed back for the report line).
    reason*: string
      ## Human-readable rationale, suitable for the watch report:
      ##   * ``weaSkip``  ⇒ ``unchanged`` (no executed function changed).
      ##   * ``weaRun``   ⇒ ``fresh`` (no cache entry), ``changed: a, b`` (the
      ##     executed functions that changed), ``non-deterministic``, or
      ##     ``error: <msg>`` (a fail-safe re-run — never a silent skip).
    changedFuncs*: seq[string]
      ## For a ``changed`` re-run, exactly the executed functions whose shallow
      ## hash changed (or which were removed). Empty otherwise.

  WatchCtIncrementalGate* = object
    ## The enable/disable gate for the `--ct-incremental` watch feature. Its zero
    ## value is the LEGACY default: `enabled == false` ⇒ the incremental decision
    ## machinery is never consulted and the watch loop follows its byte-for-byte
    ## legacy run path.
    enabled*: bool

func runDecision(testId, reason: string;
                 changedFuncs: seq[string] = @[]): WatchEdgeDecision =
  WatchEdgeDecision(action: weaRun, testId: testId, reason: reason,
                    changedFuncs: changedFuncs)

func skipDecision(testId: string): WatchEdgeDecision =
  WatchEdgeDecision(action: weaSkip, testId: testId, reason: "unchanged")

proc ctBin(): string =
  ## The codetracer ``ct`` binary to exec. Prefer ``$CT_BIN`` (CI sets it to the
  ## ``ct`` built in the codetracer sibling); otherwise rely on ``ct`` on PATH.
  let fromEnv = getEnv("CT_BIN")
  if fromEnv.len > 0: fromEnv else: "ct"

func defaultCachePath*(root = "."): string =
  ## The incremental cache path, matching codetracer's engine
  ## (``<root>/.ct-incremental/cache.json``). Pure — no engine needed.
  root / ".ct-incremental" / "cache.json"

proc runCt(mode: string; testId, traceDir, sourceRoot, cachePath: string;
           extra: seq[string] = @[]): tuple[ok: bool, output, err: string] =
  ## Exec ``ct test --incremental <mode> ...`` and capture stdout. ``ok`` is true
  ## only on exit code 0 with some stdout; otherwise ``err`` carries a diagnostic.
  let cmd = quoteShellCommand(@[ctBin(), "test", "--incremental", mode,
    "--test-id", testId, "--trace-dir", traceDir,
    "--source-root", sourceRoot, "--cache-path", cachePath] & extra)
  try:
    let (output, code) = execCmdEx(cmd)
    if code != 0:
      return (false, output, "ct exited " & $code & ": " & output.strip())
    if output.strip().len == 0:
      return (false, output, "ct produced no output")
    (true, output, "")
  except OSError as e:
    (false, "", "could not exec ct (" & ctBin() & "): " & e.msg)

proc parseJsonLine(output: string): JsonNode =
  ## Parse the last non-empty line of ``output`` as JSON (ct may emit warnings
  ## before the result line). Returns nil on failure.
  let lines = output.splitLines()
  for i in countdown(lines.high, 0):
    let s = lines[i].strip()
    if s.len == 0: continue
    try: return parseJson(s)
    except CatchableError: return nil
  nil

proc watchTestEdgeDecision*(testId, traceDir, sourceRoot, cachePath: string):
    WatchEdgeDecision =
  ## Decide skip vs. re-run for the watched test edge `testId` this cycle by
  ## execing codetracer's ``ct test --incremental --watch-decide``.
  ##
  ## Fail-safe: a missing/failed/unparseable ``ct`` forces a re-run
  ## (`weaRun`, ``error: …``) rather than a silent skip.
  let res = runCt("--watch-decide", testId, traceDir, sourceRoot, cachePath)
  if not res.ok:
    return runDecision(testId, "error: " & res.err)
  let node = parseJsonLine(res.output)
  if node.isNil or node.kind != JObject or not node.hasKey("status"):
    return runDecision(testId, "error: malformed ct output: " &
      res.output.strip())
  let status = node["status"].getStr()
  if status == "skip":
    return skipDecision(testId)
  var changed: seq[string]
  if node.hasKey("changedFuncs"):
    for c in node["changedFuncs"]:
      changed.add c.getStr()
  let reason = if node.hasKey("reason"): node["reason"].getStr() else: "run"
  runDecision(testId, reason, changed)

proc recordWatchTestEdge*(testId, traceDir, sourceRoot, cachePath: string;
                          deterministic = true): tuple[ok: bool, error: string] =
  ## Refresh the incremental cache for `testId` after a re-run, by execing
  ## codetracer's ``ct test --incremental --watch-record``. Returns the
  ## subprocess's ok/error verdict.
  let extra = if deterministic: newSeq[string]() else: @["--non-deterministic"]
  let res = runCt("--watch-record", testId, traceDir, sourceRoot, cachePath,
    extra)
  if not res.ok:
    return (false, res.err)
  let node = parseJsonLine(res.output)
  if node.isNil or node.kind != JObject or not node.hasKey("ok"):
    return (false, "malformed ct output: " & res.output.strip())
  if node["ok"].getBool():
    (true, "")
  else:
    (false, if node.hasKey("error"): node["error"].getStr() else: "record failed")

proc gatedWatchDecision*(gate: WatchCtIncrementalGate;
                         testId, traceDir, sourceRoot, cachePath: string):
    WatchEdgeDecision =
  ## The gate-aware wrapper the watch loop's no-flag path is modelled on. When
  ## the feature is DISABLED (the legacy default), this short-circuits to the
  ## legacy run verdict (`weaRun`, ``ct-incremental-disabled``) WITHOUT execing
  ## ``ct`` at all — proving the no-flag path can never skip a test. Only when
  ## the gate is enabled does it delegate to `watchTestEdgeDecision`.
  if not gate.enabled:
    return runDecision(testId, "ct-incremental-disabled")
  watchTestEdgeDecision(testId, traceDir, sourceRoot, cachePath)
