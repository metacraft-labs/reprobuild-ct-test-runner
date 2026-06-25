## t_seam_builds_against_canonical_engine — the adapter build/decoupling test.
##
## Asserts (by the very fact this binary COMPILES and runs) that
## ``ct_incremental_adapter`` builds STANDALONE — importing only std modules,
## with:
##
##   * NO codetracer engine source on the path (the engine is reached at RUNTIME
##     by execing the ``ct`` binary, not by linking ``incremental/engine``), and
##   * NO reprobuild dependency (the adapter imports nothing from reprobuild;
##     the dependency edge is one-way: this repo → codetracer's ``ct`` binary,
##     never reprobuild).
##
## If the adapter still imported codetracer's engine, this file would fail to
## compile without the engine sources/trace-format-nim/results/zstd on the path —
## so a green compile here IS the decoupling assertion. Beyond compiling, this
## asserts the seam's PUBLIC surface (the value contract reprobuild binds
## against) is present and the pure ``defaultCachePath`` helper matches the
## engine's layout.

import std/[unittest, os, strutils]

import ct_incremental_adapter

suite "adapter builds standalone (engine reached via the ct subprocess)":

  test "watch seam types are present (reprobuild's value contract)":
    # The exact union reprobuild's repro_cli_support call site binds against.
    var d = WatchEdgeDecision(action: weaSkip, testId: "t", reason: "unchanged")
    check d.action == weaSkip
    d = WatchEdgeDecision(action: weaRun, testId: "t", reason: "fresh",
                          changedFuncs: @["f"])
    check d.action == weaRun
    check d.changedFuncs == @["f"]

  test "defaultCachePath matches codetracer's engine layout":
    # The adapter replicates the engine's path (``<root>/.ct-incremental/
    # cache.json``) purely, so reprobuild computes the same cache file the ct
    # binary reads/writes.
    check defaultCachePath("/proj") == "/proj" / ".ct-incremental" / "cache.json"
    check defaultCachePath(".") == "." / ".ct-incremental" / "cache.json"

  test "watchTestEdgeDecision symbol is exported and callable":
    # With no ct on PATH/CT_BIN, the exec fails → fail-safe RUN (never skip).
    putEnv("CT_BIN", "/nonexistent/ct-binary-does-not-exist")
    let d = watchTestEdgeDecision("t", "/nonexistent/trace", "/nonexistent",
                                  "/nonexistent/cache.json")
    check d.action == weaRun                 # fail-safe — never a silent skip.
    check d.reason.startsWith("error:")
    delEnv("CT_BIN")

  test "recordWatchTestEdge symbol is exported and callable":
    putEnv("CT_BIN", "/nonexistent/ct-binary-does-not-exist")
    let r = recordWatchTestEdge("t", "/nonexistent/trace", "/nonexistent",
                                "/nonexistent/cache.json")
    check not r.ok                           # missing ct ⇒ honest failure.
    check r.error.len > 0
    delEnv("CT_BIN")
