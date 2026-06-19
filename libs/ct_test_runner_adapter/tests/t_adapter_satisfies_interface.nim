## t_adapter_satisfies_interface — adapter contract verification.
##
## Confirms that ``ctTestRunner()`` produces a ``TestRunner`` value that:
##   1. Carries a non-empty stable adapter name.
##   2. Has all three vtable procs (``run``, ``list``, ``enumerate``)
##      populated (non-nil) so the contract's ``validate`` doAssert chain
##      passes.
##   3. Survives ``validate`` without raising — i.e. is a fully legal
##      ``TestRunner`` per the cross-cutting contract declared in the
##      ``repro_test_adapters`` package.
##
## Installing the adapter into a reprobuild build context via
## ``setTestRunner`` is the *reprobuild-side* concern (this adapter no
## longer depends on the engine); that round-trip is covered by the
## ``ct_test_runner_install`` helper in the reprobuild repo.
##
## No skip()/mocks: the test exercises the real adapter constructor and
## the real interface ``validate`` proc.

import std/unittest

# ``ct_test_runner_adapter`` re-exports the ``repro_test_adapters``
# contract (``TestRunner`` / ``validate`` / …), so importing the adapter
# is enough — no engine dependency.
import ct_test_runner_adapter

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
    # The contract's validate proc raises (doAssert) on any missing
    # field. We invoke it directly; reaching the line after is the
    # assertion.
    var validated = false
    try:
      validate(runner)
      validated = true
    except AssertionDefect:
      validated = false
    check validated
    check runner.name.len > 0
    check runner.run != nil
