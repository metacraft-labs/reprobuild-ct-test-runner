## ct_test_runner_adapter — in-process ``TestRunner`` adapter.
##
## Satisfies the ``TestRunner`` cross-cutting contract declared in the
## standalone ``repro_test_adapters`` package (Nim package
## ``repro_test_adapters``; repo ``reprobuild-test-adapters``). This
## library is meant to be *linked into the reprobuild process* — the
## reprobuild project that installs it recognizes the same ``TestRunner``
## type because it depends on the same shared contract package. Hosting
## the contract there (rather than in the reprobuild engine) is what lets
## this adapter depend on the engine-free contract instead of the engine,
## so installing the adapter does not couple reprobuild back to an
## adapter repo.
##
## All three vtable methods run **in-process** against the test binary's
## own protocol — there is no longer a separate ``ct-test-runner``
## orchestrator executable to locate or spawn:
##
##   * ``run``  — execute the binary. With no filter the binary runs its
##     whole suite and its native exit code is forwarded; with a filter
##     the binary's ``--run "<suite>::<test>"`` single-test protocol is
##     used.
##   * ``list`` — query the binary's ``--list-json`` catalog.
##   * ``enumerate`` — query the binary's ``--list`` (one qualified name
##     per line).
##
## The build context wiring (``setTestRunner``) lives on the consumer
## side: a reprobuild project installs this adapter by calling
## ``currentBuildContext().setTestRunner(ctTestRunner())`` (see the
## reprobuild-side ``install_ct_test_runner`` helper), so this library
## carries no dependency on the reprobuild engine — only on the shared
## ``repro_test_adapters`` contract.

import std/[json, os, osproc, strutils]

import repro_test_adapters
export repro_test_adapters

proc parseListJsonCatalog(payload: string): seq[TestCase] =
  ## Parse the binary's ``--list-json`` output. Schema (Tier-1
  ## "Standard"): a top-level object with a ``tests`` array whose entries
  ## carry ``suite`` and ``name`` fields. ``name`` may already be
  ## qualified (``suite::test``); the parser normalises so
  ## ``qualifiedName`` always includes the suite prefix once.
  result = @[]
  let trimmed = payload.strip()
  if trimmed.len == 0:
    return
  let doc =
    try:
      parseJson(trimmed)
    except JsonParsingError:
      return
  if not doc.hasKey("tests") or doc["tests"].kind != JArray:
    return
  for entry in doc["tests"]:
    let suite = entry{"suite"}.getStr("")
    let name = entry{"name"}.getStr("")
    if name.len == 0:
      continue
    var bareName = name
    if suite.len > 0 and name.startsWith(suite & "::"):
      bareName = name[len(suite) + 2 .. ^1]
    let qualified =
      if suite.len > 0: suite & "::" & bareName
      else: bareName
    let display =
      if bareName.len > 0: bareName
      else: qualified
    result.add(TestCase(qualifiedName: qualified, displayName: display))

proc adapterRunInvocation(binary: TestBinary; filter: string): ExitCode =
  ## Run the test binary in-process (as a direct child of the reprobuild
  ## process). With no filter the binary runs its whole suite; with a
  ## filter the binary's ``--run "<name>"`` single-test protocol selects
  ## one case. The binary's native exit code is forwarded verbatim
  ## (0 pass / non-zero fail), matching the contract's ``run`` semantics.
  if binary.path.len == 0:
    return -1
  var argv: seq[string] = @[quoteShell(binary.path)]
  if filter.len > 0:
    # The binary's single-test protocol is ``--run "<suite>::<test>"``.
    argv.add("--run")
    argv.add(quoteShell(filter))
  try:
    execShellCmd(argv.join(" "))
  except OSError:
    -1

proc adapterListInvocation(binary: TestBinary): seq[TestCase] =
  ## Query the binary's own ``--list-json`` protocol entry point and
  ## return the structured catalog. The binary is the source of truth for
  ## its case list.
  if binary.path.len == 0:
    return @[]
  let (output, exitCode) =
    try:
      execCmdEx(quoteShell(binary.path) & " --list-json")
    except CatchableError:
      ("", -1)
  if exitCode != 0:
    return @[]
  parseListJsonCatalog(output)

proc adapterEnumerateInvocation(binary: TestBinary): seq[QualifiedName] =
  ## Query the binary's ``--list`` protocol entry point — one qualified
  ## name per line. Skips blank lines so partial output from a malformed
  ## binary doesn't produce empty entries.
  if binary.path.len == 0:
    return @[]
  let (output, exitCode) =
    try:
      execCmdEx(quoteShell(binary.path) & " --list")
    except CatchableError:
      ("", -1)
  if exitCode != 0:
    return @[]
  for raw in output.splitLines():
    let line = raw.strip()
    if line.len == 0:
      continue
    result.add(line)

proc ctTestRunner*(): TestRunner =
  ## Construct a fully populated ``TestRunner`` whose vtable runs the test
  ## binary in-process via its own ``--run`` / ``--list-json`` / ``--list``
  ## protocol. The reprobuild project installs the returned value via the
  ## active build context's ``setTestRunner`` (engine-side; see the
  ## reprobuild ``install_ct_test_runner`` helper).
  newTestRunner(
    name = "ct-test-runner-adapter",
    run = proc(binary: TestBinary; filter: string): ExitCode =
      adapterRunInvocation(binary, filter),
    list = proc(binary: TestBinary): seq[TestCase] =
      adapterListInvocation(binary),
    enumerate = proc(binary: TestBinary): seq[QualifiedName] =
      adapterEnumerateInvocation(binary))
