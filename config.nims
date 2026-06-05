switch("styleCheck", "hint")
switch("path", "libs/ct_test_interface/src")
switch("path", "libs/ct_test_nim_unittest/src")
switch("path", "libs/ct_test_unittest_parallel/src")

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
