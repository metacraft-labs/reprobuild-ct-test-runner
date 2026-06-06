set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    just lint

build:
    mkdir -p build/bin build/nimcache
    nim c \
        -d:release \
        --threads:on \
        --hints:off \
        --warnings:off \
        --nimcache:build/nimcache/ct_test_runner \
        --out:build/bin/ct-test-runner \
        apps/ct-test-runner/ct_test_runner.nim

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
