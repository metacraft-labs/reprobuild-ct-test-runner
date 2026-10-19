## Complete thirteen-module owning corpus; no engine imports.
## Existing scripted incremental protocol fixtures retain their owning header
## justification. Four existing orchestrator-availability skips remain a
## separate qualification gap, never evidence of full acceptance.
import repro_project_dsl
import repro_dsl_stdlib/foreign_env
import ct_test_nim_unittest

const serialPool = "ct_test_runner.serial"
type
  Sublib = enum
    slUnittestParallel, slRunnerAdapter, slIncremental, slRoot
  CtTestSpec = object
    sublib: Sublib
    stem: string
    forksNimCompile: bool
proc spec(sublib: Sublib; stem: string; forksNimCompile = false): CtTestSpec =
  CtTestSpec(sublib: sublib, stem: stem, forksNimCompile: forksNimCompile)

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
  spec(slIncremental, "t_adapter_incremental_seam"),
  spec(slIncremental, "t_seam_builds_against_canonical_engine"),
  spec(slRoot, "t_nimcache_is_worktree_local"),
]


package ct_test_runner:
  devEnv:
    when not defined(windows):
      useFlakeDevShell()
  defaultToolProvisioning "path"
  uses:
    "nim >=2.2 <3.0"
    when defined(macosx):
      "clang >=15"
    else:
      "gcc >=12"
    when not defined(windows):
      "sh"
  build:
    discard buildPool(serialPool, 1)
    var builds, executes: seq[BuildActionDef] = @[]
    let paths = @["libs/ct_test_unittest_parallel/src",
      "libs/ct_test_runner_adapter/src", "libs/ct_incremental_adapter/src",
      "../reprobuild-test-adapters/src", "../reprobuild/libs/ct_test_interface/src"]
    let inputs = @["libs", "tests", "config.nims", "ct_test.nimble", "scripts/run_tests.sh",
      "../reprobuild-test-adapters/src", "../reprobuild/libs/ct_test_interface/src"]
    for s in ctTestSpecs:
      let source = case s.sublib
        of slUnittestParallel: "libs/ct_test_unittest_parallel/tests/" & s.stem & ".nim"
        of slRunnerAdapter: "libs/ct_test_runner_adapter/tests/" & s.stem & ".nim"
        of slIncremental: "libs/ct_incremental_adapter/tests/" & s.stem & ".nim"
        of slRoot: "tests/" & s.stem & ".nim"
      let edge = buildNimUnittest.build(source = source,
        binary = "build/test-bin/" & s.stem, paths = paths,
        actionId = "ct_test_runner.test_build." & s.stem, extraInputs = inputs)
      let backendRefs = when defined(macosx): @["clang"] else: @["gcc"]
      appendRegisteredActionToolIdentityRefs(edge.action.id, backendRefs)
      builds.add(edge.action)
      let execution = edge.testBinary.run(
        actionId = "ct_test_runner.test_execute." & s.stem,
        extraInputs = inputs,
        pool = (if s.forksNimCompile: serialPool else: ""),
        registerImplicitName = false)
      if s.forksNimCompile:
        appendRegisteredActionToolIdentityRefs(execution.id, @["nim"] & backendRefs)
      elif s.sublib == slRoot:
        appendRegisteredActionToolIdentityRefs(execution.id, @["nim"])
      when not defined(windows):
        appendRegisteredActionToolIdentityRefs(execution.id, @["sh"])
      executes.add(execution)
    discard collect("test", executes)
    discard collect("test-builds", builds)
