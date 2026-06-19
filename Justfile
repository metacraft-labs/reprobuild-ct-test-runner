set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    just lint

build:
    @echo "reprobuild-ct-test-runner is a library (ct_test_runner_adapter)."
    @echo "Nothing to build as a binary; run 'just test' to compile + run the suite."

test:
    mkdir -p test-logs
    bash scripts/run_tests.sh 2>&1 | tee test-logs/test.log

t: test

lint:
    mkdir -p test-logs
    bash scripts/check_nim_sources.sh 2>&1 | tee test-logs/lint.log

format:
    @echo "No formatter wired up yet."

fmt: format
