## ct_test_nim_unittest — Nim unittest adapter for the codetracer
## test framework.
##
## Exports:
##
## * ``NimUnittestBinary`` — the typed handle. Reprobuild binds a
##   ``path: string`` value into it via ``outputs testBinary is
##   NimUnittestBinary, binary``.
##
## * ``buildNimUnittest.build(...)`` — a reprobuild typed-tool that
##   compiles a Nim unittest test binary. Declared via
##   ``defineCliInterface``; the ``outputs testBinary is
##   NimUnittestBinary, binary`` typed-output statement makes the
##   build edge's return value carry a populated ``testBinary``
##   handle.
##
## * ``run(self: NimUnittestBinary; ...)``,
##   ``runTest(self: NimUnittestBinary; ...)``,
##   ``list(self: NimUnittestBinary; ...)`` — UFCS dispatch procs that
##   emit execution edges. The boilerplate shape matches what a
##   follow-on auto-generation milestone will eventually emit from a
##   CLI-only ``executable NimUnittestBinary`` declaration; today the
##   procs are hand-authored.
##
## Standalone usage (no reprobuild edge emission) still works for the
## bare type — a user can construct ``NimUnittestBinary(path: "...")``
## directly and invoke the binary by any conventional means.

import ct_test_interface
export ct_test_interface

import repro_project_dsl
export repro_project_dsl

const NimUnittestToolId* = "ct_test_nim_unittest.buildNimUnittest"

type
  NimUnittestBinary* = object
    ## Typed handle for a Nim ``unittest`` test binary. Carries the
    ## binary path so UFCS method calls like ``handle.run(...)`` can
    ## route the path into execution-edge input sets.
    path*: string

defineCliInterface buildNimUnittest, NimUnittestToolId:
  subcmd "build":
    flag source is string,
      role = input,
      required = true
    flag binary is string,
      role = output,
      required = true
    boolFlag threadsOn is bool, alias = "--threads:on"
    boolFlag hintsOff is bool, alias = "--hints:off"
    boolFlag warningsOff is bool, alias = "--warnings:off"
    flag defines is seq[string],
      alias = "--define:",
      format = concat,
      repeated = true
    flag imports is seq[string],
      alias = "--import:",
      format = concat,
      repeated = true
    outputs testBinary is NimUnittestBinary, binary

proc run*(self: NimUnittestBinary; filter = "";
          actionId = ""; deps: openArray[string] = [];
          after: openArray[BuildActionDef] = []): BuildActionDef
    {.discardable.} =
  ## Emit one execution edge that runs the test binary. The bound
  ## ``self.path`` flows in as a synthesised ``binary`` input flag so
  ## the action cache keys on the binary content.
  var cliArgs: seq[PublicCliArg] = @[]
  cliArgs.add(inputArg("binary", self.path))
  if filter.len > 0:
    cliArgs.add(cliArg("filter", filter))
  let call = publicCliCall(NimUnittestToolId, NimUnittestToolId,
    "run", NimUnittestToolId & ".run", cliArgs)
  let selectedActionId =
    if actionId.len > 0: actionId
    else: defaultToolActionId(call)
  result = recordToolInvocation(selectedActionId, call,
    deps = combineActionDeps(deps, after),
    dependencyPolicy = declaredOnlyDependencyPolicy())
  let implicitNames = computeImplicitTargetNames(call, @["binary"])
  if implicitNames.len > 0:
    setRegisteredActionTargetNames(result.id, implicitNames)
    registerImplicitTargetExports(result.id,
      NimUnittestToolId, implicitNames,
      "ct_test_nim_unittest.nim", 0)

proc runTest*(self: NimUnittestBinary; testName: string;
              actionId = ""; deps: openArray[string] = [];
              after: openArray[BuildActionDef] = []): BuildActionDef
    {.discardable.} =
  ## Emit an execution edge that runs exactly one named test inside
  ## the binary. The ``testName`` is expected in the
  ## ``<suite>::<test>`` form per the codetracer parallel test
  ## framework spec.
  var cliArgs: seq[PublicCliArg] = @[]
  cliArgs.add(inputArg("binary", self.path))
  cliArgs.add(cliArg("run", testName))
  let call = publicCliCall(NimUnittestToolId, NimUnittestToolId,
    "runTest", NimUnittestToolId & ".runTest", cliArgs)
  let selectedActionId =
    if actionId.len > 0: actionId
    else: defaultToolActionId(call)
  result = recordToolInvocation(selectedActionId, call,
    deps = combineActionDeps(deps, after),
    dependencyPolicy = declaredOnlyDependencyPolicy())
  let implicitNames = computeImplicitTargetNames(call, @["binary"])
  if implicitNames.len > 0:
    setRegisteredActionTargetNames(result.id, implicitNames)
    registerImplicitTargetExports(result.id,
      NimUnittestToolId, implicitNames,
      "ct_test_nim_unittest.nim", 0)

proc list*(self: NimUnittestBinary;
           actionId = ""; deps: openArray[string] = [];
           after: openArray[BuildActionDef] = []): BuildActionDef
    {.discardable.} =
  ## Emit an enumeration edge that lists the binary's test cases.
  ## Reprobuild's action cache memoises this until the binary
  ## content changes.
  var cliArgs: seq[PublicCliArg] = @[]
  cliArgs.add(inputArg("binary", self.path))
  cliArgs.add(cliArg("list-json", true))
  let call = publicCliCall(NimUnittestToolId, NimUnittestToolId,
    "list", NimUnittestToolId & ".list", cliArgs)
  let selectedActionId =
    if actionId.len > 0: actionId
    else: defaultToolActionId(call)
  result = recordToolInvocation(selectedActionId, call,
    deps = combineActionDeps(deps, after),
    dependencyPolicy = declaredOnlyDependencyPolicy())
  let implicitNames = computeImplicitTargetNames(call, @["binary"])
  if implicitNames.len > 0:
    setRegisteredActionTargetNames(result.id, implicitNames)
    registerImplicitTargetExports(result.id,
      NimUnittestToolId, implicitNames,
      "ct_test_nim_unittest.nim", 0)
