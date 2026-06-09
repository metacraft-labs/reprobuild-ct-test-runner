## t_adapter_satisfies_interface — Spec-Implementation M4 verification.
##
## Confirms that ``ctTestRunner()`` produces a ``TestRunner`` value
## that:
##   1. Carries a non-empty stable adapter name.
##   2. Has all three vtable procs (``run``, ``list``, ``enumerate``)
##      populated (non-nil) so the M3 ``validate`` doAssert chain
##      passes.
##   3. Survives ``validate`` without raising — i.e. is a fully
##      legal ``TestRunner`` per the cross-cutting interface contract
##      declared in
##      ``reprobuild/libs/repro_dsl_stdlib/src/repro_dsl_stdlib/interfaces/test_runner.nim``.
##   4. Round-trips through the ``setTestRunner(ctx, runner)`` slot
##      installer on a freshly minted ``BuildContext`` (cast back
##      cleanly to ``TestRunner``).
##
## No skip()/mocks: the test exercises the real adapter constructor
## and the real M3 interface ``validate`` proc.

import std/unittest

import ct_test_runner_adapter
import repro_dsl_stdlib/interfaces/test_runner
import repro_dsl_stdlib/active_context
import repro_project_dsl

suite "t_adapter_satisfies_interface":
  test "ctTestRunner returns a fully populated TestRunner":
    let runner = ctTestRunner()
    check runner != nil
    check runner.name == "ct-test-runner-adapter"
    check runner.run != nil
    check runner.list != nil
    check runner.enumerate != nil

  test "validate(runner) does not raise":
    let runner = ctTestRunner()
    # The M3 validate proc raises (doAssert) on any missing field.
    # We invoke it directly; reaching the line after is the assertion.
    var validated = false
    try:
      validate(runner)
      validated = true
    except AssertionDefect:
      validated = false
    check validated
    check runner.name.len > 0
    check runner.run != nil

  test "setTestRunner installs adapter into a build context slot":
    # Use the package macro's beginBuildBlock/endBuildBlock pair to
    # synthesise an active context so the slot machinery is live.
    let state = beginBuildBlock("t_adapter_satisfies_interface")
    defer: endBuildBlock(state)

    let ctx = currentBuildContext()
    let runner = ctTestRunner()
    setTestRunner(ctx, runner)

    # The slot now carries the adapter; the typed accessor downcasts
    # ``RootRef`` to ``TestRunner`` and returns the same identity.
    let echoed = ctx.testRunner
    check echoed != nil
    check echoed.name == "ct-test-runner-adapter"
    check echoed.run != nil
    check echoed.list != nil
