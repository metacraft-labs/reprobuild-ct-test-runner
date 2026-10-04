# ct-test Agent Instructions

## Commands

- Build: `just build`
- Test: `just test`
- Lint: `just lint`
- Format: `just format`

## Structure

- `libs/` contains importable Nim libraries. One per framework adapter plus
  the core `ct_test_interface` library.
- `apps/` (future) holds the `ct-test-runner` binary.
- `tests/` contains repository-level tests.
- `docs/` contains framework-author documentation.

## Boundaries

- **ct-test does NOT import or depend on reprobuild's engine.** The interface this repo
  declares (`TestBinary`, `TestResultsHandle`, `TestCatalogHandle`) is
  consumed by reprobuild's typed-output machinery, but the dependency edge
  goes one way: reprobuild knows about ct-test; ct-test stays standalone.
  The generic observation adapter does depend on the import-free
  `ct_test_interface` schema contract currently hosted in reprobuild/libs.
  `config.nims` resolves `CT_TEST_INTERFACE_SRC`, or `REPROBUILD_SRC`, or the
  sibling checkout. This source dependency does not import the engine.

- Per-framework adapter modules (`ct_test_nim_unittest`, future
  `ct_test_cargo`, etc.) live in separate `libs/` directories so consumers
  can import only the adapters they need.

- `ct-test-runner` (when it ships) speaks the Tier-1 "Standard" binary
  protocol per
  [Nim-Parallel-Test-Framework.md §3.6](https://github.com/metacraft-labs/codetracer-specs/blob/main/Planned-Features/Nim-Parallel-Test-Framework.md).
  It probes binaries to identify their framework when no reprobuild static
  annotation is available.

## Workspace coupling

This repo lives next to `reprobuild`, `runquota`, and `codetracer` under the
metacraft workspace. The relevant cross-repo dependencies:

- Reprobuild's `repro.nim` (or generated `repro.tests.nim`) will `uses:` the
  per-framework adapter modules from this repo.
- The `TestBinary` Nim-type fields (`path: string` and structural conventions)
  are the reprobuild–ct-test contract.

When the workspace lock is refreshed (`workspace lock`), reprobuild pins a
specific revision of this repo.
