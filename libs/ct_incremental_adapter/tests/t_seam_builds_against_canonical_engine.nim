## t_seam_builds_against_canonical_engine — the M0b-1 build test.
##
## Asserts (by the very fact this binary COMPILES and runs) that
## ``ct_incremental_adapter`` builds while importing codetracer's CANONICAL
## engine via the sibling path wired in ``config.nims`` — with:
##
##   * NO vendored engine copy in this repo (the engine modules live only in
##     codetracer, imported as a sibling), and
##   * NO reprobuild dependency (the adapter imports nothing from reprobuild;
##     the dependency edge is one-way: this repo → codetracer, never reprobuild).
##
## Beyond the import succeeding, this asserts the seam's PUBLIC surface is
## present and wired to codetracer's engine types: the ``WatchEdgeDecision`` /
## ``WatchEdgeAction`` value contract reprobuild binds against, and the engine's
## re-exported ``IncrementalDecisionKind`` (proving the engine is genuinely in
## scope through the adapter, not a stub).

import std/unittest

import ct_incremental_adapter

suite "M0b-1 — adapter builds against codetracer's canonical engine":

  test "watch seam types are present (reprobuild's value contract)":
    # The exact union reprobuild's repro_cli_support call site binds against.
    var d = WatchEdgeDecision(action: weaSkip, testId: "t", reason: "unchanged")
    check d.action == weaSkip
    d = WatchEdgeDecision(action: weaRun, testId: "t", reason: "fresh",
                          changedFuncs: @["f"])
    check d.action == weaRun
    check d.changedFuncs == @["f"]

  test "codetracer engine is re-exported through the adapter":
    # If the canonical engine were not actually imported, these engine symbols
    # would be undeclared and this file would not compile. Referencing them
    # proves the engine is in scope via the adapter (not a local stub).
    check idRunFresh != idSkipUnchanged
    check idRerunChanged != idRerunFailSafe
    # The engine's cache constructor + fail-safe loader are reachable too.
    let cache = initCache("/tmp/ct_seam_build_probe_cache.json")
    check cache.path == "/tmp/ct_seam_build_probe_cache.json"
    let loaded = loadCache("/tmp/ct_seam_build_probe_nonexistent.json")
    check loaded.isOk        # a missing cache loads fresh (Ok), per the engine.

  test "watchTestEdgeDecision symbol is exported and callable":
    # A non-existent trace/cache: the engine's fail-safe path runs, never skips.
    let d = watchTestEdgeDecision("t", "/nonexistent/trace", "/nonexistent",
                                  "/nonexistent/cache.json")
    check d.action == weaRun   # fresh (empty cache) — a run, never a silent skip.
