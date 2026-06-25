## t_adapter_incremental_seam — the watch-decision seam protocol test.
##
## Proves that ``watchTestEdgeDecision`` / ``recordWatchTestEdge`` correctly
## SPEAK the granular ``ct test --incremental --watch-decide`` / ``--watch-record``
## protocol: they exec the ``ct`` binary, parse its one-line JSON, and map it to
## the ``WatchEdgeDecision`` / ok-error contract reprobuild binds against.
##
## The adapter's responsibility is the PROCESS SEAM (exec + parse + map +
## fail-safe), NOT the decision itself — codetracer's engine owns and tests the
## decision. So here we drive the seam with a FAKE ``ct`` (a tiny script pointed
## to by ``$CT_BIN``) that emits scripted JSON for each engine outcome, and
## assert the adapter's mapping and, crucially, its fail-safe behavior:
##
##   * ``{"status":"skip"}``               ⇒ ``weaSkip`` (``reason == "unchanged"``)
##   * ``{"status":"run","reason":"fresh"}`` ⇒ ``weaRun`` (``reason == "fresh"``)
##   * ``{"status":"run","reason":"changed: used_a","changedFuncs":["used_a"]}``
##                                          ⇒ ``weaRun`` naming ``used_a``
##   * ct exits non-zero                    ⇒ ``weaRun`` fail-safe (``error: …``)
##   * ct emits unparseable output          ⇒ ``weaRun`` fail-safe (``error: …``)
##   * ct missing entirely                  ⇒ ``weaRun`` fail-safe (``error: …``)
##   * gate disabled                        ⇒ ``weaRun`` WITHOUT execing ct
##
## A fail-safe is ALWAYS a re-run, never a silent skip: losing/breaking the
## engine binary can never cause a test that should run to be skipped.

import std/[unittest, os, strutils]

import ct_incremental_adapter

# ---------------------------------------------------------------------------
# A fake `ct` binary: emits $CT_FAKE_OUT to stdout and exits $CT_FAKE_CODE.
# Pointed to via $CT_BIN, it lets us script every engine outcome the adapter
# must map — without codetracer's engine present.
# ---------------------------------------------------------------------------

let fakeCt = getTempDir() / "ct_fake_seam.sh"

proc installFakeCt() =
  writeFile(fakeCt, "#!/bin/sh\nprintf '%s\\n' \"$CT_FAKE_OUT\"\nexit ${CT_FAKE_CODE:-0}\n")
  inclFilePermissions(fakeCt, {fpUserExec, fpGroupExec, fpOthersExec})
  putEnv("CT_BIN", fakeCt)

proc setFake(output: string; code = 0) =
  putEnv("CT_FAKE_OUT", output)
  putEnv("CT_FAKE_CODE", $code)

proc decideWith(output: string; code = 0): WatchEdgeDecision =
  setFake(output, code)
  watchTestEdgeDecision("t::id", "/trace", "/root", "/cache.json")

suite "watch-decision seam — ct subprocess protocol":

  setup:
    installFakeCt()

  teardown:
    delEnv("CT_BIN"); delEnv("CT_FAKE_OUT"); delEnv("CT_FAKE_CODE")

  test "skip status maps to weaSkip":
    let d = decideWith("""{"status":"skip","reason":"unchanged","changedFuncs":[]}""")
    check d.action == weaSkip
    check d.reason == "unchanged"
    check d.testId == "t::id"

  test "fresh run maps to weaRun":
    let d = decideWith("""{"status":"run","reason":"fresh","changedFuncs":[]}""")
    check d.action == weaRun
    check d.reason == "fresh"

  test "changed run forwards reason + changedFuncs verbatim":
    let d = decideWith(
      """{"status":"run","reason":"changed: used_a","changedFuncs":["used_a"]}""")
    check d.action == weaRun
    check d.reason == "changed: used_a"
    check d.changedFuncs == @["used_a"]

  test "non-zero ct exit is a fail-safe run (never a silent skip)":
    let d = decideWith("""{"status":"skip","reason":"unchanged"}""", code = 1)
    check d.action == weaRun
    check d.reason.startsWith("error:")

  test "unparseable ct output is a fail-safe run":
    let d = decideWith("not json at all")
    check d.action == weaRun
    check d.reason.startsWith("error:")

  test "ct emitting warnings before the JSON line still parses":
    # ct may print hints/warnings before the result; the adapter reads the LAST
    # non-empty line as JSON.
    let d = decideWith("warning: something\n{\"status\":\"skip\"}")
    check d.action == weaSkip

  test "recordWatchTestEdge maps ok":
    setFake("""{"ok":true,"error":""}""")
    let r = recordWatchTestEdge("t::id", "/trace", "/root", "/cache.json")
    check r.ok
    check r.error == ""

  test "recordWatchTestEdge maps an engine error":
    setFake("""{"ok":false,"error":"trace missing"}""")
    let r = recordWatchTestEdge("t::id", "/trace", "/root", "/cache.json")
    check not r.ok
    check r.error == "trace missing"

  test "recordWatchTestEdge fail-safes on non-zero ct exit":
    setFake("""{"ok":true}""", code = 2)
    let r = recordWatchTestEdge("t::id", "/trace", "/root", "/cache.json")
    check not r.ok
    check r.error.len > 0

suite "watch-decision seam — gate + missing-binary fail-safe":

  test "gate disabled short-circuits to run WITHOUT execing ct":
    # CT_BIN points at a bomb that would FAIL if executed; the disabled gate must
    # never reach it.
    putEnv("CT_BIN", "/nonexistent/ct-should-not-run")
    let gate = WatchCtIncrementalGate(enabled: false)
    let d = gatedWatchDecision(gate, "t::id", "/trace", "/root", "/cache.json")
    check d.action == weaRun
    check d.reason == "ct-incremental-disabled"
    delEnv("CT_BIN")

  test "missing ct binary is a fail-safe run":
    putEnv("CT_BIN", "/nonexistent/ct-does-not-exist")
    let d = watchTestEdgeDecision("t::id", "/trace", "/root", "/cache.json")
    check d.action == weaRun
    check d.reason.startsWith("error:")
    delEnv("CT_BIN")
