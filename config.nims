switch("styleCheck", "hint")
switch("path", "libs/ct_test_interface/src")
switch("path", "libs/ct_test_nim_unittest/src")
switch("path", "libs/ct_test_unittest_parallel/src")
# Spec-Implementation M4: ``ct_test_runner_adapter`` lives alongside
# ``ct_test_nim_unittest``; the M4 adapter test binaries and the
# integration shape both import it directly.
switch("path", "libs/ct_test_runner_adapter/src")

# The Nim-unittest adapter declares an `executable` using reprobuild's
# project DSL. The DSL source lives in the sibling reprobuild repo.
# Workspace-relative paths follow the runquota/reprobuild convention of
# using fixed-input env vars resolved by the dev shell or by manual export.
when fileExists("../reprobuild/libs/repro_project_dsl/src/repro_project_dsl.nim"):
  switch("path", "../reprobuild/libs/repro_project_dsl/src")
  switch("path", "../reprobuild/libs/repro_dsl_stdlib/src")

# Source-only deps the reprobuild DSL transitively needs.
when fileExists("../reprobuild/libs/repro_core/src/repro_core.nim"):
  switch("path", "../reprobuild/libs/repro_core/src")

# Spec-Implementation M4: ``ct_test_runner_adapter`` imports
# ``repro_dsl_stdlib/active_context`` which transitively pulls in
# ``configurables/variants`` (the M2d solver-driven finalize path);
# ``variants.nim`` imports ``repro_solver/variant_encoder`` and friends.
# Expose the solver sources so the adapter and its M4 tests type-check
# against the live stdlib surface.
when fileExists("../reprobuild/libs/repro_solver/src/repro_solver.nim"):
  switch("path", "../reprobuild/libs/repro_solver/src")
