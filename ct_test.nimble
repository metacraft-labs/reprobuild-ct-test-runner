version = "0.1.0"
author = "Metacraft Labs"
description = "reprobuild in-process TestRunner adapter (ct_test_runner_adapter) + test-binary protocol lib"
license = "MIT"
srcDir = "src"

requires "nim >= 2.2.0"

task build, "No binary to build — this repo is a library":
  exec "just build"

task test, "Run the ct-test repo test suite":
  exec "just test"
