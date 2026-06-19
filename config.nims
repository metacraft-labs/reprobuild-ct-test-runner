switch("styleCheck", "hint")

# The run-side ``ct_test_runner_adapter`` and ``ct_test_unittest_parallel``
# — the test-binary protocol lib the adapter's round-trip tests build
# sample binaries against.
switch("path", "libs/ct_test_unittest_parallel/src")
switch("path", "libs/ct_test_runner_adapter/src")

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
