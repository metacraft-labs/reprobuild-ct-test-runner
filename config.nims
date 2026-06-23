import std/[os, strutils]

switch("styleCheck", "hint")

# The run-side ``ct_test_runner_adapter`` and ``ct_test_unittest_parallel``
# — the test-binary protocol lib the adapter's round-trip tests build
# sample binaries against.
switch("path", "libs/ct_test_unittest_parallel/src")
switch("path", "libs/ct_test_runner_adapter/src")

# The ``ct_incremental_adapter`` — the watch-integration incremental-decision
# seam (``watchTestEdgeDecision`` / ``WatchEdgeDecision``), backed by
# codetracer's CANONICAL engine.
switch("path", "libs/ct_incremental_adapter/src")

# --------------------------------------------------------------------------
# codetracer canonical incremental engine (no vendored copy)
# --------------------------------------------------------------------------
#
# ``ct_incremental_adapter`` imports codetracer's canonical engine
# (``codetracer/src/ct_test/incremental/engine.nim``) directly as a workspace
# SIBLING — the whole point of M0b is that reprobuild consumes the canonical
# engine with NO vendored copy and NO drift. The engine's transitive imports
# stay within codetracer's ``ct_test/incremental`` modules plus
# codetracer-trace-format-nim's seekable CTFS reader; it pulls in NO reprobuild,
# runquota, or io-mon module (verified: ``engine`` → ``ctfs_trace`` →
# ``ctfs_seekable`` → ``codetracer_trace_writer/new_trace_reader`` +
# ``codetracer_ct_print_lib``, and the native chain
# ``native_trace`` → ``native_instrument`` → ``native_hash``, all self-contained
# over std + ``results`` + the trace-format-nim package).
#
# The wiring below MIRRORS codetracer's own ``src/ct_test/config.nims`` +
# ``nim.cfg`` (the only build configuration that makes the engine compile): the
# engine module path, the codetracer-trace-format-nim sibling path, the
# ``results >= 0.5`` pin its seekable reader needs (codetracer-trace-format-nim's
# ``?`` operator expands to the ``.v`` field that version introduced), and the
# zstd dev include for the trace-format-nim CTFS reader's ``#include <zstd.h>``.
# Every path is defended with ``dirExists``/``fileExists`` so a checkout missing
# the codetracer sibling fails LOUDLY at compile time (undeclared ``engine``)
# rather than silently mis-resolving — exactly how codetracer's own config
# guards the trace-format-nim fallback.

proc wireCodetracerEngine() =
  # 1. The canonical engine module directory. Resolved from
  #    ``CODETRACER_CT_TEST_SRC`` (the dev shell / CI sets it to
  #    ``codetracer/src/ct_test``) or from the sibling checkout next to this
  #    repo for local development.
  let ctTestSrc =
    if getEnv("CODETRACER_CT_TEST_SRC").len > 0:
      getEnv("CODETRACER_CT_TEST_SRC")
    else:
      "../codetracer/src/ct_test"
  let engineDir = ctTestSrc / "incremental"
  if fileExists(engineDir / "engine.nim"):
    switch("path", engineDir)

  # 2. codetracer-trace-format-nim — the package the engine's seekable
  #    executed-function reader (``ctfs_seekable.nim``) links. Resolved from
  #    ``CODETRACER_TRACE_FORMAT_NIM_SRC`` (codetracer's own config uses the same
  #    env var) or the sibling checkout.
  let traceFormatSrc =
    if getEnv("CODETRACER_TRACE_FORMAT_NIM_SRC").len > 0:
      getEnv("CODETRACER_TRACE_FORMAT_NIM_SRC")
    else:
      "../codetracer-trace-format-nim/src"
  if fileExists(traceFormatSrc / "codetracer_ct_print_lib.nim"):
    switch("path", traceFormatSrc)

  # 3. ``results >= 0.5`` pin (same resolution order as codetracer's
  #    ``config.nims``: env var, then the newest ``results-0.5*`` under
  #    ``~/.nimble/pkgs2``). codetracer-trace-format-nim needs the ``.v`` field
  #    the ``?`` operator expands to; the older vendored ``results`` lacks it.
  block pinResults:
    let envSrc = getEnv("CODETRACER_RESULTS_SRC")
    if envSrc.len > 0 and dirExists(envSrc):
      switch("path", envSrc)
      break pinResults
    let pkgs2 = getHomeDir() / ".nimble" / "pkgs2"
    if dirExists(pkgs2):
      var best = ""
      for kind, p in walkDir(pkgs2):
        if kind == pcDir and p.lastPathPart.startsWith("results-0.5"):
          if p.lastPathPart > best.lastPathPart:
            best = p
      if best.len > 0:
        switch("path", best)

  # 4. zstd dev include for the trace-format-nim CTFS reader's
  #    ``#include <zstd.h>`` — re-surfaced out of the nix cc-wrapper's
  #    ``NIX_CFLAGS_COMPILE`` exactly as codetracer's ``config.nims`` does.
  #    No-op outside Nix (the env var carries no zstd include) and harmless when
  #    the wrapper already supplied it (a duplicate ``-isystem`` is a no-op).
  let nixCflags = getEnv("NIX_CFLAGS_COMPILE")
  if nixCflags.len > 0:
    let toks = nixCflags.splitWhitespace()
    var i = 0
    while i < toks.len:
      if toks[i] == "-isystem" and i + 1 < toks.len:
        let dir = toks[i + 1]
        if "zstd" in dir:
          switch("passC", "-isystem " & dir)
        i += 2
      else:
        i += 1

wireCodetracerEngine()

# The adapter depends only on the engine-free ``repro_test_adapters``
# contract (Nim package ``repro_test_adapters``, repo
# ``reprobuild-test-adapters``) — no reprobuild engine sources are needed
# any more. Resolve the contract from ``REPRO_TEST_ADAPTERS_SRC`` (the dev
# shell / CI sets it) or from a sibling checkout for local development.
let reproTestAdaptersSrc =
  if getEnv("REPRO_TEST_ADAPTERS_SRC").len > 0:
    getEnv("REPRO_TEST_ADAPTERS_SRC")
  else:
    "../reprobuild-test-adapters/src"
if dirExists(reproTestAdaptersSrc):
  switch("path", reproTestAdaptersSrc)
