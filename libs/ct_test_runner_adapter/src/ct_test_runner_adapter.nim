## ct_test_runner_adapter — in-process, framework-aware ``TestRunner``.
##
## Satisfies the ``TestRunner`` cross-cutting contract from the standalone
## ``repro_test_adapters`` package and is meant to be *linked into the
## reprobuild process*: the reprobuild project that installs it recognizes
## the same ``TestRunner`` type because it depends on the same contract.
##
## All three vtable methods run **in-process** against the test binary —
## there is no separate ``ct-test-runner`` orchestrator executable.
##
## ## Indicating the test framework
##
## Different test binaries speak different command-line protocols, so the
## adapter cannot assume one shape for every binary. The framework is
## indicated **per binary** through ``TestBinary.metadata`` (the contract's
## adapter-specific metadata field). Construct a tagged binary with
## ``testBinary(path, framework)``; an empty/unrecognised tag falls back to
## ``DefaultFramework`` so existing untagged binaries keep their behaviour.
## ``ctTestRunner`` reads the tag and dispatches RUN / LIST / ENUMERATE to
## the matching protocol handler.
##
## Adding a framework is two edits: a new ``TestFramework`` enum value and
## a branch in each of the three ``case`` dispatchers below.
##
## The engine-coupled install (``setTestRunner``) is the consumer's
## concern — a reprobuild project installs this via the reprobuild-side
## ``ct_test_runner_install`` helper — so this library depends only on the
## engine-free contract.

import std/[json, os, osproc, strutils]

import repro_test_adapters
export repro_test_adapters

type
  TestFramework* = enum
    ## How the adapter talks to a built test binary. Indicated per-binary
    ## through ``TestBinary.metadata`` (use ``testBinary`` to tag one).
    tfCtTestParallel = "ct-test-parallel"
      ## Binaries linking ``ct_test_unittest_parallel``: the rich protocol
      ## — run a single case with ``--run "<suite>::<test>"``; enumerate
      ## with ``--list`` (one qualified name per line) and ``--list-json``
      ## (a structured catalog).
    tfDirect = "direct"
      ## A self-contained test executable with no introspection protocol:
      ## ``run`` execs it directly (a non-empty filter is forwarded as a
      ## single positional argument, e.g. a Nim ``std/unittest`` glob);
      ## ``list`` / ``enumerate`` synthesise one entry from the binary's
      ## basename, since the binary cannot be queried for its case list.

const DefaultFramework* = tfCtTestParallel
  ## The framework assumed when a ``TestBinary`` carries no (or an
  ## unrecognised) framework tag — keeps pre-framework binaries working.

proc frameworkOf*(binary: TestBinary): TestFramework =
  ## The framework indicated by ``binary.metadata``. An empty or
  ## unrecognised tag falls back to ``DefaultFramework``.
  let tag = binary.metadata.strip()
  if tag.len == 0:
    return DefaultFramework
  try:
    parseEnum[TestFramework](tag)
  except ValueError:
    DefaultFramework

proc testBinary*(path: string; framework = DefaultFramework): TestBinary =
  ## Construct a framework-tagged ``TestBinary``: the framework id is
  ## encoded into ``metadata`` so ``ctTestRunner`` dispatches RUN / LIST /
  ## ENUMERATE to the matching protocol handler.
  TestBinary(path: path, metadata: $framework)

# --------------------------------------------------------------------------
# ``ct-test-parallel`` protocol (binaries linking ct_test_unittest_parallel)
# --------------------------------------------------------------------------

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

proc runCtTestParallel(path, filter: string): ExitCode =
  ## Run the binary; with a filter use its ``--run "<suite>::<test>"``
  ## single-case protocol. Native exit code forwarded verbatim.
  var argv: seq[string] = @[quoteShell(path)]
  if filter.len > 0:
    argv.add("--run")
    argv.add(quoteShell(filter))
  try:
    execShellCmd(argv.join(" "))
  except OSError:
    -1

proc listCtTestParallel(path: string): seq[TestCase] =
  let (output, exitCode) =
    try:
      execCmdEx(quoteShell(path) & " --list-json")
    except CatchableError:
      ("", -1)
  if exitCode != 0:
    return @[]
  parseListJsonCatalog(output)

proc enumerateCtTestParallel(path: string): seq[QualifiedName] =
  let (output, exitCode) =
    try:
      execCmdEx(quoteShell(path) & " --list")
    except CatchableError:
      ("", -1)
  if exitCode != 0:
    return @[]
  for raw in output.splitLines():
    let line = raw.strip()
    if line.len == 0:
      continue
    result.add(line)

# --------------------------------------------------------------------------
# ``direct`` protocol (arbitrary self-contained test executables)
# --------------------------------------------------------------------------

proc runDirect(path, filter: string): ExitCode =
  ## Exec the binary as-is; a non-empty filter is a single positional
  ## argument (the convention a Nim ``std/unittest`` binary honours as a
  ## glob). The binary's native exit code is forwarded.
  var argv: seq[string] = @[quoteShell(path)]
  if filter.len > 0:
    argv.add(quoteShell(filter))
  try:
    execShellCmd(argv.join(" "))
  except OSError:
    -1

proc directSyntheticName(path: string): string =
  ## A direct binary can't be introspected; its basename stands in for the
  ## single addressable "case".
  path.extractFilename()

proc listDirect(path: string): seq[TestCase] =
  let name = directSyntheticName(path)
  @[TestCase(qualifiedName: name, displayName: name)]

proc enumerateDirect(path: string): seq[QualifiedName] =
  @[directSyntheticName(path)]

# --------------------------------------------------------------------------
# Framework dispatch
# --------------------------------------------------------------------------

proc adapterRunInvocation(binary: TestBinary; filter: string): ExitCode =
  if binary.path.len == 0:
    return -1
  case frameworkOf(binary)
  of tfCtTestParallel: runCtTestParallel(binary.path, filter)
  of tfDirect: runDirect(binary.path, filter)

proc adapterListInvocation(binary: TestBinary): seq[TestCase] =
  if binary.path.len == 0:
    return @[]
  case frameworkOf(binary)
  of tfCtTestParallel: listCtTestParallel(binary.path)
  of tfDirect: listDirect(binary.path)

proc adapterEnumerateInvocation(binary: TestBinary): seq[QualifiedName] =
  if binary.path.len == 0:
    return @[]
  case frameworkOf(binary)
  of tfCtTestParallel: enumerateCtTestParallel(binary.path)
  of tfDirect: enumerateDirect(binary.path)

proc ctTestRunner*(): TestRunner =
  ## Construct a fully populated ``TestRunner`` whose vtable runs each test
  ## binary in-process via the protocol indicated by that binary's
  ## framework tag (``TestBinary.metadata``; see ``testBinary`` /
  ## ``TestFramework``). The reprobuild project installs the returned value
  ## via the active build context's ``setTestRunner`` (engine-side; see the
  ## reprobuild ``ct_test_runner_install`` helper).
  newTestRunner(
    name = "ct-test-runner-adapter",
    run = proc(binary: TestBinary; filter: string): ExitCode =
      adapterRunInvocation(binary, filter),
    list = proc(binary: TestBinary): seq[TestCase] =
      adapterListInvocation(binary),
    enumerate = proc(binary: TestBinary): seq[QualifiedName] =
      adapterEnumerateInvocation(binary))
