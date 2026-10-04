# ct-test

> **Status:** Bootstrap. Just the foundational types and DSL declarations needed
> to unblock reprobuild's typed-output suite migration.

CodeTracer's test framework, packaged as the Nim modules and the future
`ct-test-runner` binary. Reprobuild consumes the per-framework adapter
modules (`ct_test_nim_unittest`, future `ct_test_cargo`, …) to identify
test binaries and dispatch enumeration / per-test execution as ordinary
build-graph edges.

The asymmetric coupling: **reprobuild knows the `TestBinary` interface
declared here; ct-test does NOT import reprobuild's engine**. `ct-test-runner`
will work standalone (e.g. against binaries produced by `nim c` directly)
via its own probing logic; reprobuild's static type annotations on the
`outputs` statement are an optimization, not a requirement.

## Libraries

- [`libs/ct_test_interface/`](libs/ct_test_interface/) — the `TestBinary`
  Nim interface (a base record / typeclass shape) and the
  `TestResultsHandle` / `TestCatalogHandle` value types reprobuild's
  typed-output machinery binds against.
- [`libs/ct_test_nim_unittest/`](libs/ct_test_nim_unittest/) — adapter for
  Nim's `std/unittest`. Defines `NimUnittestBinary` (the typed handle) and
  `buildNimUnittest` (the typed-tool that produces the binary).

## Future work

Per the [Reprobuild-CI-Sharding-Support
campaign](https://github.com/metacraft-labs/codetracer-specs/blob/main/Planned-Features/Reprobuild-CI-Sharding-Support.milestones.org)
in codetracer-specs:

- `ct-test-runner` minimum-features runner — process-per-test, multi-binary,
  `--partition file:`, counter-mode console reporter.
- Per-framework adapter expansion (`ct_test_cargo`, `ct_test_pytest`,
  `ct_test_go`).
- Tier-1 "Standard" binary protocol (`--list-json` / `--run` /
  `NIMTEST_RESULT_FILE`) inside each test binary.

See `docs/` for design discussion.

## Building and testing

The observation adapter uses the leaf `ct_test_interface` schema package in
the sibling reprobuild checkout. Set `CT_TEST_INTERFACE_SRC` to its `src`
directory, or `REPROBUILD_SRC` to an alternate checkout, when using another
layout. This is a compile-time schema dependency, not an engine dependency.

```bash
just build      # build any apps (none yet)
just test       # run repo tests
just lint       # static checks
```

This repo follows the metacraft Nim-library conventions used by
[`reprobuild`](../reprobuild) and [`runquota`](../runquota).
