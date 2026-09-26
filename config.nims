import std/[os, strutils]

switch("styleCheck", "hint")

# The run-side ``ct_test_runner_adapter`` and ``ct_test_unittest_parallel``
# — the test-binary protocol lib the adapter's round-trip tests build
# sample binaries against.
switch("path", "libs/ct_test_unittest_parallel/src")
switch("path", "libs/ct_test_runner_adapter/src")

# The ``ct_incremental_adapter`` — the watch-integration incremental-decision
# seam (``watchTestEdgeDecision`` / ``recordWatchTestEdge`` / ``WatchEdgeDecision``).
# It reaches codetracer's CANONICAL engine by EXECUTING the ``ct`` binary as a
# subprocess (the ``ct test --incremental --watch-decide`` / ``--watch-record``
# protocol), so it compiles against std only — NO codetracer engine source,
# trace-format-nim, results, or zstd is needed on the path. The dependency on
# codetracer is a one-way RUNTIME process dependency (resolved from ``$CT_BIN``
# or ``ct`` on PATH), not a compile/link dependency.
switch("path", "libs/ct_incremental_adapter/src")

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

# Imported packages do not execute their config.nims. Resolve the adapter's
# leaf schema contract here as well, without importing any engine library.
let runnerRoot = currentSourcePath().parentDir()
let reprobuildRoot = getEnv("REPROBUILD_SRC", runnerRoot / ".." / "reprobuild")
let ctTestInterfaceSrc = getEnv("CT_TEST_INTERFACE_SRC",
  reprobuildRoot / "libs" / "ct_test_interface" / "src")
if dirExists(ctTestInterfaceSrc):
  switch("path", ctTestInterfaceSrc)

## Worktree-local nimcache: every Nim compile inside this checkout keeps its
## intermediate files (its nimcache) INSIDE this checkout.
##
## WHY.  Nim's default nimcache is `$XDG_CACHE_HOME/nim/<project>_d` (`_r` for
## -d:release; `%USERPROFILE%\nimcache\<project>_d` on Windows).  It is keyed by
## the project NAME only, and the generated file names inside it do not depend
## on the checkout path either.  So two worktrees or clones of this repository
## that build the same project at the same time write, compile and link each
## other's intermediate files.  Measured on 2026-09-26 in a sibling repository:
## ten concurrent builds of two worktrees that differed in a few places gave
## four correct binaries, two that exited 0 with the OTHER worktree's code
## linked in (one of them a mix of both), two compile failures on
## half-rewritten generated C and two link failures.
##
## WHAT.  `<checkout>/.nimcache/<directory of the main module, relative to the
## checkout>/<module name><suffix>`, where the suffix is Nim's own: `_check`
## for `nim check`, `_r` for -d:release or -d:danger, `_d` otherwise.  The
## directory is part of the key, so same-named modules in different directories
## no longer share a cache either.  Only the intermediates move; build outputs
## stay where they were.  An explicit `--nimcache:` on the command line still
## wins, because Nim applies the command line again after the config files.
## `nim js` and project-less invocations are left alone.
##
## HOW IT IS PICKED UP.  Nim runs the `config.nims` of every PARENT directory of
## the compiled module, outermost first, then the one in the module's own
## directory.  So this file applies to every compile under this checkout,
## `just`, `nimble`, CI and a bare `nim c` alike, whatever the working directory.
## `--skipParentCfg` switches it off for modules below the checkout root, so a
## recipe that passes that flag must name its own checkout-local `--nimcache:`.
## Nothing in this repository passes `--skipParentCfg` today; `scripts/run_tests.sh`
## names its own `--nimcache:build/nimcache/<test>`, inside the checkout.
## `tests/t_nimcache_is_worktree_local.nim` checks the layout, and fails if the
## config is bypassed; its `--skipParentCfg` negative control proves the probe
## can see a shared cache at all.
##
## WINDOWS.  Nim turns the `/` below into `\` on a Windows host.  The layout adds
## `\.nimcache\<module dir>\<module>_d\` in front of Nim's own object file names,
## so keep the checkout root short (about 80 characters) to stay inside MAX_PATH.
block worktreeLocalNimcache:
  var project = projectName()
  if project.len > 4 and project[^4 .. ^1] == ".nim":
    project = project[0 ..< ^4]
  # No project (`nim dump` with no file): nothing to place.  The JS backend
  # has its own convention (a cache next to its output).  `nim e` never
  # generates C, so it never creates the directory.
  if project.len == 0 or getCommand() == "js":
    break worktreeLocalNimcache

  # Plain "/" joins, NOT std/os `/`: NimScript's `/` follows the TARGET OS,
  # so a `--os:windows` cross-compile on a POSIX host would get backslashes.
  let root = thisDir()
  let projDir = projectDir()
  var rel = ""
  if projDir.len >= root.len and projDir[0 ..< root.len] == root:
    rel = projDir[root.len .. ^1]
  else:
    # Cannot happen for a project Nim found this file for (this file is read
    # because it sits in a parent of the project directory).  Stay inside
    # the checkout and stay unique anyway.
    rel = "_outside/"
    for c in projDir:
      rel.add(if c in {'/', '\\', ':'}: '_' else: c)
  while rel.len > 0 and rel[0] in {'/', '\\'}:
    rel = rel[1 .. ^1]

  let suffix =
    if getCommand() == "check": "_check"
    elif defined(release) or defined(danger): "_r"
    else: "_d"
  var cacheDir = root & "/.nimcache"
  if rel.len > 0:
    cacheDir.add("/" & rel)
  switch("nimcache", cacheDir & "/" & project & suffix)
