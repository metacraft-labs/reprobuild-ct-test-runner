## Reprobuild project file for reprobuild-ct-test-runner.
##
## **Typed-Cross-Project-Deps rollout — the in-process CodeTracer TestRunner
## adapter, a single-sibling Nim CONSUMER (SC-11 develop-mode from-source
## sibling consumption).** This repo is a LIBRARY collection of three
## importable sub-libraries under ``libs/<lib>/src`` — the test-binary
## protocol shim ``ct_test_unittest_parallel``, the framework-aware
## in-process ``ct_test_runner_adapter``, and the watch-integration
## ``ct_incremental_adapter`` — with 13 tests total spread across their
## ``tests/`` directories. Its ``config.nims`` wires each sub-lib's ``src``
## onto ``--path`` and resolves two external seams: the engine-free
## ``repro_test_adapters`` contract (a LANDED workspace sibling) and
## codetracer's canonical incremental engine (the out-of-scope main
## product).
##
## **The three sub-libs split cleanly by dependency (grep-verified against
## every test's ``import`` block):**
##
##   * ``ct_test_unittest_parallel`` (6 tests) — a LEAF sub-lib. Every test
##     imports only ``std/*`` and (for the smoke test) the in-repo
##     ``ct_test_unittest_parallel`` shim itself. No landed-sibling and no
##     out-of-scope dependency. Five of the six spawn ``nim c`` at RUNTIME
##     (via ``execCmd`` / ``execCmdEx``) to compile a self-contained
##     fixture under ``tests/fixtures/`` and drive it through the shim's
##     ``--list`` / ``--list-json`` / ``--run`` protocol — resolving the
##     shim ``src`` and the fixture through ``currentSourcePath()`` relative
##     paths, and invoking ``nim`` from ``PATH``. Two of those five
##     (``t_ct_test_runner_full_suite_parity`` /
##     ``t_ct_test_runner_partition_file_mode``) additionally probe for a
##     built ``ct-test-runner`` / ``repro_test_runner`` orchestrator binary
##     under a workspace root located by walking for a directory containing
##     BOTH ``ct-test`` and ``reprobuild`` children; under a hermetic
##     reprobuild sandbox that walk fails, so both self-``checkpoint("skipped
##     …")`` and exit 0 (the exit-0 verification the engine keys on) — NOT a
##     regression, just an optional-fixture skip. All six are host-runnable
##     and MODELLED green.
##
##   * ``ct_test_runner_adapter`` (4 tests) — imports ``ct_test_runner_adapter``,
##     whose ``src`` does ``import repro_test_adapters`` (re-exporting the
##     ``TestRunner`` cross-cutting contract). That resolves to the LANDED
##     sibling ``reprobuild-test-adapters`` (mainline 2cd37a9, ships
##     ``library repro_test_adapters`` — the umbrella ``src/repro_test_adapters.nim``).
##     Expressed the reprobuild-native way: ``uses: "reprobuild-test-adapters"``
##     names the PRODUCER by its workspace directory; reprobuild builds it
##     from source (its ``library`` edge) and threads its ``src/`` root onto
##     this repo's ``nim c --path:`` via the SC-11 ``nimPathDirs`` aux
##     channel — replacing ``config.nims``'s ``REPRO_TEST_ADAPTERS_SRC`` /
##     ``../reprobuild-test-adapters/src`` literal. All four are MODELLED
##     green.
##
##   * ``ct_incremental_adapter`` (2 tests) — imports ``ct_incremental_adapter``,
##     whose ``src`` does ``import engine`` (re-exporting it). That resolves
##     ONLY to codetracer's canonical
##     ``../codetracer/src/ct_test/incremental/engine.nim`` (there is no
##     vendored copy; ``config.nims``'s ``wireCodetracerEngine`` threads it
##     from the codetracer sibling). codetracer is the huge main product and
##     is OUT OF SCOPE for this campaign — it has NO ``repro.nim`` and will
##     get none — so these two tests are a legitimate DOCUMENTED DEFERRAL
##     (see the deferral note below). They are NOT disabled in the repo and
##     NOT weakened; they simply cannot be modelled until codetracer lands a
##     recipe.
##
## Net: **10 of 13 tests are MODELLED green** (6 leaf + 4 adapter);
## **2 are DEFERRED** (codetracer engine, out of scope). The prior SKIP was
## because BOTH consumed siblings lacked a ``repro.nim``; one
## (``reprobuild-test-adapters``) has now landed, un-SKIP-ping the adapter
## arm, while the other (``codetracer``) remains out of scope.
##
## **No reprobuild-INTERNAL ``paths:`` needed.** This repo's own
## ``libs/ct_test_unittest_parallel/src`` is a LOCAL sub-lib (not the
## same-named reprobuild-internal ``reprobuild/libs/ct_test_unittest_parallel``
## engine copy); the tests' ``import ct_test_unittest_parallel`` resolves to
## the LOCAL tree via each edge's ``paths:``. No edge imports a
## reprobuild-internal lib (``ct_test_interface`` / ``ct_test_nim_unittest``
## are only the RECIPE's DSL-runtime imports, supplied by the engine — not
## a test dependency), so no ``../reprobuild/libs/<lib>/src`` third-party
## thread is required on any modelled edge.
##
## A Mode 1 / Mode 3 hybrid (per
## ``reprobuild-specs/Three-Mode-Convention-System.md``) modelled on the
## landed single-consumer recipes ``reprobuild-test-adapters/repro.nim``
## (the producer) and ``isonim-tui/repro.nim`` (the multi-sibling consumer),
## and the ``codetracer-visual-replay/repro.nim`` two-sibling develop-mode
## consumer:
##
## * Declares the toolchain floor via ``uses:`` (``nim`` + ``gcc``) plus the
##   ONE landed sibling ``uses: "reprobuild-test-adapters"`` edge. Mirrors
##   the nimble file's ``requires "nim >= 2.2.0"`` and ``config.nims``'s
##   ``repro_test_adapters`` resolution.
## * Emits, per MODELLED test file, a BUILD edge (``buildNimUnittest.build``)
##   that compiles ``build/test-bin/<stem>`` and an EXECUTE edge
##   (``edge.testBinary.run``) that runs it — the two-edge test template from
##   ``reprobuild-specs/Package-Model.md`` §"The test template". BUILD halves
##   collect into ``test-builds``; EXECUTE halves into ``test`` so
##   ``repro build test`` / ``repro test`` materialise the runnable closure
##   (each execute edge transitively depends on its build edge).
##
## **Compile profile.** ``scripts/run_tests.sh`` compiles every test with a
## bare ``nim c -r --threads:on --hints:off --warnings:off`` (no ``--mm``, no
## ``-d:release``): the wrapper defaults. Each edge reproduces that — the
## ``buildNimUnittest.build`` defaults already carry ``--threads:on
## --hints:off --warnings:off``, and no ``mm`` / ``defines`` override is
## warranted. The leaf edges get ``paths = @["libs/ct_test_unittest_parallel/src"]``
## (the shim ``src`` its smoke test imports and its fixtures resolve at
## runtime); the adapter edges get
## ``paths = @["libs/ct_test_runner_adapter/src", "libs/ct_test_unittest_parallel/src"]``
## (the adapter ``src`` the test imports plus the shim ``src`` the run-round-trip
## fixtures compile against at runtime), with the ``reprobuild-test-adapters``
## ``src`` threaded off the ``uses:`` ``nimPathDirs`` channel — NOT spelled
## here. Each edge's whole owning sub-lib ``src`` + ``tests`` trees are
## declared ``extraInputs`` so the monitor tracks the transitively imported
## modules and the runtime-compiled fixtures.
##
## **Runtime ``nim`` provisioning.** The five leaf tests + the three
## adapter round-trip/dispatch tests fork ``nim c`` at RUNTIME to compile a
## fixture. ``defaultToolProvisioning "path"`` puts the nix dev shell's
## ``nim`` + ``gcc`` on the environment the execute edge inherits, so those
## in-test compiles resolve the same toolchain the BUILD edge used — the
## reprobuild-native equivalent of ``run_tests.sh`` running under
## ``nix develop``.
##
## **Nested-``nim c`` serialisation.** EIGHT of the ten modelled tests fork a
## nested ``nim c`` at RUNTIME to compile a fixture (the five
## fixture-compiling leaf tests + the three ``t_adapter_*`` round-trip /
## dispatch / list tests); only ``t_smoke_ct_test_unittest_parallel`` and
## ``t_adapter_satisfies_interface`` are pure in-process contract checks with
## no subprocess. Run in parallel their concurrent Nim compiles + linked
## child binaries oversubscribe the host and NONDETERMINISTICALLY signal-kill
## a fixture compile / child run (observed as a sporadic ``exit -1`` or an
## all-``[SKIPPED]``-yet-``exit 1`` on a ROTATING subset — a scheduler-load
## artefact, not an assertion failure: every test case itself reports
## ``[OK]`` / ``[SKIPPED]``). They are assigned a capacity-1 build pool
## (``ct_test_runner.serial``) via ``pool = serialPool`` on their EXECUTE
## edges — the reprobuild-native way to SERIALISE resource-contending tests
## WITHOUT touching any assertion (nothing skipped or weakened, only
## scheduled), exactly as ``isonim-tui/repro.nim`` pools its real-pty tests.
## The two subprocess-free tests stay unpooled (full parallelism).
##
## Two product hardening fixes ship WITH this recipe (committed first, as
## product fixes): ``t_every_test_binary_speaks_list_json_protocol`` and
## ``t_test_binary_run_one_writes_result_file`` both compiled their
## ``fixture_protocol_three_tests`` fixture to the SAME
## ``build/test-bin/ct_test_unittest_parallel_fixture_three_tests`` output
## path + nimcache, so running them in parallel let one binary's ``nim c``
## clobber the other's freshly-linked binary mid-exec (a genuine ``exit 126``
## "Permission denied" race independent of the pool). Each now tags its
## fixture output path / nimcache with the running test-binary name
## (``getAppFilename``) and invokes the fixture by ABSOLUTE path — a grounded
## de-collision, no assertion changed.
##
## ==========================================================================
## DEFERRAL — the two ``ct_incremental_adapter`` tests (codetracer, out of scope)
## ==========================================================================
##
## ``libs/ct_incremental_adapter/tests/t_adapter_incremental_seam.nim`` and
## ``libs/ct_incremental_adapter/tests/t_seam_builds_against_canonical_engine.nim``
## both ``import ct_incremental_adapter``, whose ``src`` does ``import
## engine`` / ``export engine`` — resolving ONLY to codetracer's canonical
## ``../codetracer/src/ct_test/incremental/engine.nim`` (no vendored copy;
## see this repo's ``config.nims`` ``wireCodetracerEngine`` + the adapter's
## module docstring). ``codetracer`` is the out-of-scope main product with no
## ``repro.nim`` (and none planned in this campaign), so these two tests
## cannot be expressed as a ``uses:`` sibling-from-source consumption and
## cannot be threaded from a landed producer. They are DEFERRED here —
## re-model them when codetracer lands a recipe (its
## ``src/ct_test/incremental`` engine would then be a ``uses: "codetracer"``
## producer, or the engine tree an explicit third-party ``paths:`` thread
## with its trace-format-nim / results / zstd wiring, per ``config.nims``).
## NOT disabled in the repo, NOT weakened — just out of the modelled closure.
##
## **Tool provisioning.** ``defaultToolProvisioning "path"`` matches the
## canonical recipes: the nix dev shell puts ``nim`` + ``gcc`` on ``PATH``,
## so the weak-local PATH resolver is the right default. It is also required
## for the ``uses:`` declarations to resolve at all ("typed tool provisioning
## is required for uses declarations").

import repro_project_dsl

# ``ct_test_nim_unittest`` supplies the ``buildNimUnittest.build(...)``
# typed-tool used by every test BUILD edge and the ``edge.testBinary.run(...)``
# UFCS dispatch for the EXECUTE edges. It re-exports ``repro_project_dsl`` so
# the import order is unimportant. Like the landed consumer recipes this file
# does NOT import ``ct_test_runner_install`` (engine-coupled,
# reprobuild-internal): the execute edges route through the engine's default
# direct-binary runner (run the binary, key on exit status), which is exactly
# the exit-0 verification this corpus needs — Nim ``unittest`` prints per-suite
# results and exits non-zero on failure.
import ct_test_nim_unittest

const
  # The two importable sub-lib ``src`` roots the modelled tests resolve
  # (the third, ``ct_incremental_adapter/src``, backs only the two deferred
  # codetracer tests and is not on any modelled edge).
  unittestParallelSrc = "libs/ct_test_unittest_parallel/src"
  runnerAdapterSrc = "libs/ct_test_runner_adapter/src"

  # Capacity-1 pool that serialises the eight tests which fork a NESTED
  # ``nim c`` at runtime to compile a fixture (see the nested-compile note in
  # the module docstring). Running all eight in parallel oversubscribes the
  # host with concurrent Nim compiles + their linked child binaries, which
  # nondeterministically signal-kills a fixture compile / child run (observed
  # as sporadic ``exit -1`` / all-``[SKIPPED]``-yet-``exit 1`` on a rotating
  # subset). Serialising them removes the contention WITHOUT touching any
  # assertion — exactly the ``buildPool`` mechanism ``isonim-tui/repro.nim``
  # uses for its real-pty tests.
  serialPool = "ct_test_runner.serial"

type
  Sublib = enum
    ## Which sub-lib a test lives under — selects its ``paths:`` /
    ## ``extraInputs`` and (for the adapter sub-lib) whether the
    ## ``reprobuild-test-adapters`` ``uses:`` thread applies.
    slUnittestParallel  ## LEAF — std + in-repo shim only.
    slRunnerAdapter     ## consumes ``repro_test_adapters`` (landed sibling).

  CtTestSpec = object
    ## One entry per MODELLED test file. ``sublib`` selects the sub-lib
    ## directory + build inputs; ``stem`` is the ``tests/<stem>.nim`` source
    ## / ``build/test-bin/<stem>`` output basename. ``forksNimCompile`` marks
    ## the tests that fork a NESTED ``nim c`` (to compile a fixture) at RUNTIME
    ## — those run through the capacity-1 ``ct_test_runner.serial`` pool (see
    ## the nested-compile serialisation note in the module docstring).
    sublib: Sublib
    stem: string
    forksNimCompile: bool

proc spec(sublib: Sublib; stem: string; forksNimCompile = false): CtTestSpec =
  CtTestSpec(sublib: sublib, stem: stem, forksNimCompile: forksNimCompile)

# The MODELLED corpus — 10 of the repo's 13 tests (the two
# ``ct_incremental_adapter`` tests are DEFERRED; see the deferral note).
const ctTestSpecs: seq[CtTestSpec] = @[
  # ---- ct_test_unittest_parallel (6 leaf tests, std + in-repo shim) ----
  # ``t_smoke`` is the only leaf that does NOT fork ``nim c`` at runtime; the
  # other five compile a fixture in-process and so are serialised.
  spec(slUnittestParallel, "t_smoke_ct_test_unittest_parallel"),
  spec(slUnittestParallel, "t_backward_compat_std_unittest_test_runs_unchanged",
    forksNimCompile = true),
  spec(slUnittestParallel, "t_every_test_binary_speaks_list_json_protocol",
    forksNimCompile = true),
  spec(slUnittestParallel, "t_test_binary_run_one_writes_result_file",
    forksNimCompile = true),
  spec(slUnittestParallel, "t_ct_test_runner_full_suite_parity",
    forksNimCompile = true),
  spec(slUnittestParallel, "t_ct_test_runner_partition_file_mode",
    forksNimCompile = true),
  # ---- ct_test_runner_adapter (4 tests, consume repro_test_adapters) ----
  # ``t_adapter_satisfies_interface`` is a pure in-process contract check (no
  # subprocess); the other three fork ``nim c`` to compile adapter fixtures.
  spec(slRunnerAdapter, "t_adapter_satisfies_interface"),
  spec(slRunnerAdapter, "t_adapter_list_and_enumerate",
    forksNimCompile = true),
  spec(slRunnerAdapter, "t_adapter_framework_dispatch",
    forksNimCompile = true),
  spec(slRunnerAdapter, "t_adapter_run_round_trip",
    forksNimCompile = true),
]

package ct_test_runner:
  defaultToolProvisioning "path"

  uses:
    # Toolchain floor — the PATH-resolvable binaries the build needs.
    # ``nim`` compiles every test binary (the ``buildNimUnittest.build``
    # edges below, matching the nimble file's ``requires "nim >= 2.2.0"``)
    # and is ALSO forked at runtime by the fixture-compiling tests; ``gcc``
    # is the C back-end ``nim c`` shells out to. Sufficient for the
    # path-mode resolver under ``nix develop``.
    "nim >=2.2 <3.0"
    "gcc >=12"

    # The one landed sibling Nim-library producer the adapter tests consume
    # from source (SC-11 develop-mode). Naming the workspace directory here
    # makes reprobuild build the sibling from source (its ``library
    # repro_test_adapters`` edge) and thread its ``src/`` root onto this
    # repo's ``nim c --path:`` via the ``nimPathDirs`` aux channel —
    # replacing ``config.nims``'s ``REPRO_TEST_ADAPTERS_SRC`` /
    # ``../reprobuild-test-adapters/src`` literal so ``import
    # ct_test_runner_adapter`` → ``import repro_test_adapters`` resolves.
    "reprobuild-test-adapters"   # library repro_test_adapters

  build:
    # Two-edge test template (Package-Model.md §"The test template"): one
    # compile BUILD edge + one EXECUTE edge per test file. BUILD halves
    # collect into ``test-builds`` (compile verification); EXECUTE halves
    # into ``test`` so ``repro test`` / ``repro build test`` materialise the
    # runnable closure (each execute edge transitively depends on its build
    # edge). Compile flags reproduce ``scripts/run_tests.sh`` (a bare
    # ``nim c -r --threads:on --hints:off --warnings:off``): the
    # ``buildNimUnittest.build`` defaults already carry those three flags,
    # so no ``mm`` / ``defines`` override is spelled.
    #
    # Capacity-1 pool for the eight nested-``nim c`` tests (see the
    # ``serialPool`` note above): threaded onto their EXECUTE edges below so
    # they never run concurrently, removing the host oversubscription that
    # nondeterministically signal-killed a rotating subset.
    discard buildPool(serialPool, 1)

    var testBuildActions: seq[BuildActionDef] = @[]
    var testExecuteActions: seq[BuildActionDef] = @[]

    for s in ctTestSpecs:
      let (subdir, paths, extraInputs) =
        case s.sublib
        of slUnittestParallel:
          # LEAF: the shim ``src`` (its smoke test imports it; its
          # runtime-compiled fixtures resolve it via a relative ``../src``).
          # Declare the whole sub-lib ``src`` + ``tests`` trees (the
          # ``tests/fixtures`` dir is compiled at runtime) + the nimble file
          # as inputs.
          ("libs/ct_test_unittest_parallel",
           @[unittestParallelSrc],
           @["libs/ct_test_unittest_parallel/src",
             "libs/ct_test_unittest_parallel/tests",
             "libs/ct_test_unittest_parallel/ct_test_unittest_parallel.nimble"])
        of slRunnerAdapter:
          # ADAPTER: the adapter ``src`` (the test imports it) + the shim
          # ``src`` (the run-round-trip fixtures compile against it at
          # runtime). ``repro_test_adapters`` ``src`` arrives off the
          # ``uses:`` ``nimPathDirs`` channel — NOT listed here. Declare both
          # sub-lib ``src`` + the adapter ``tests`` + the adapter nimble file
          # as inputs.
          ("libs/ct_test_runner_adapter",
           @[runnerAdapterSrc, unittestParallelSrc],
           @["libs/ct_test_runner_adapter/src",
             "libs/ct_test_unittest_parallel/src",
             "libs/ct_test_runner_adapter/tests",
             "libs/ct_test_runner_adapter/ct_test_runner_adapter.nimble"])

      let source = subdir & "/tests/" & s.stem & ".nim"
      let binary = "build/test-bin/" & s.stem

      let edge = buildNimUnittest.build(
        source = source,
        binary = binary,
        paths = paths,
        actionId = "ct_test_runner.test_build." & s.stem,
        extraInputs = extraInputs)
      testBuildActions.add(edge.action)

      # ``registerImplicitName = false``: the BUILD edge already owns the
      # binary basename as the implicit target name; the explicit ``actionId``
      # is the execute edge's selector (two-edge shape). The eight tests that
      # fork a nested ``nim c`` at runtime route through the capacity-1
      # ``serialPool`` so they never run concurrently (host oversubscription
      # guard); the two pure in-process tests stay unpooled (full parallelism).
      let executeEdge =
        if s.forksNimCompile:
          edge.testBinary.run(
            actionId = "ct_test_runner.test_execute." & s.stem,
            pool = serialPool,
            registerImplicitName = false)
        else:
          edge.testBinary.run(
            actionId = "ct_test_runner.test_execute." & s.stem,
            registerImplicitName = false)
      testExecuteActions.add(executeEdge)

    discard collect("test", testExecuteActions)
    discard collect("test-builds", testBuildActions)
