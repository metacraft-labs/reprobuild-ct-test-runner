## ct_test_runner — Test-Edges-And-Parallel-Runner M4
##
## External protocol-level parallel runner for Nim test binaries that
## speak the Tier-1 "Standard" binary protocol shipped in
## ``ct_test_unittest_parallel`` (M2):
##
## * ``--list-json``                — JSON catalog of test cases
## * ``--run "<suite>::<test>"``    — execute one named test
## * ``$NIMTEST_RESULT_FILE``       — JSON result document path
## * exit codes 0/1/2               — pass/fail/skip
##
## This is the M4 port of reprobuild's M3 internal runner
## (``tools/test-runner/repro_test_runner.nim``). It keeps the same
## protocol contract, worker-pool architecture, ``--threads`` /
## ``$REPRO_TEST_FAIL_FAST`` behaviour, and JSON summary shape. New in
## M4: ``--partition file:<path>`` reads a list of fully-qualified test
## names and runs only those.
##
## Mixed mode: binaries that don't speak the protocol (e.g. existing
## ``import std/unittest`` tests that haven't migrated yet) are detected
## at probe time and executed whole; their single exit code becomes the
## edge's pass/fail status.
##
## Concurrency: process-per-test (exec-per-test). N worker tasks pull
## from a shared queue protected by a single ``Lock``; the main thread
## blocks on a barrier until every worker drains the queue.
##
## CLI::
##
##   ct-test-runner run [BINARY...]
##                      [--threads N] [--bin-dir DIR]
##                      [--partition file:<path>]
##                      [--summary-json PATH] [--quiet]
##                      [--filter SUBSTR]...
##                      [--results-dir DIR]
##
## When one or more ``BINARY`` arguments are passed positionally, the
## runner uses exactly those binaries (and skips ``--bin-dir`` scanning).
## With no positional binaries, behaviour matches the M3 runner: the
## runner scans ``--bin-dir`` (default ``build/test-bin``) for
## ``t_*`` / ``test_*`` executables. The ``run`` subcommand is optional
## for backward compatibility with the M3 CLI shape.
##
## Environment::
##
##   REPRO_TEST_FAIL_FAST=1   stop scheduling new tests after first FAIL
##   REPRO_TEST_THREADS=N     override default worker count
##
## See also: codetracer-specs/Planned-Features/Nim-Parallel-Test-Framework.md
## §15.1 for the canonical partition spec; only ``file:`` is implemented
## in M4 (``slice:`` and ``hash:`` are CI-Sharding territory).

import std/[algorithm, json, locks, os, osproc, parseopt, sets,
            strutils, times]

const
  DefaultBinDir = "build/test-bin"
  DefaultResultsSubdir = "test-logs/results"
  DefaultSummaryPath = "test-logs/parallel-run.json"

  ## Test-binary basenames that are excluded from runner discovery.
  ## ``ct_test_runner`` / ``repro_test_runner`` are this binary and its
  ## predecessor (self-spawn would recurse).
  ExcludeStems = [
    "ct_test_runner",
    "ct-test-runner",
    "repro_test_runner",
  ]

type
  TestCase = object
    binary: string          ## absolute path to the compiled test binary
    binaryStem: string      ## file basename without extension
    protocolAware: bool     ## true if the binary speaks --list-json
    qualifiedName: string   ## ``suite::test``; "" when whole-binary
    suite: string
    name: string

  TestStatus = enum
    tsPass = "PASS"
    tsFail = "FAIL"
    tsSkip = "SKIP"

  TestResult = object
    testCase: TestCase
    status: TestStatus
    durationMs: int
    resultFile: string
    stdout: string
    stderr: string

  Queue = object
    lock: Lock
    items: seq[TestCase]
    pos: int            ## next index to hand out
    failFastTriggered: bool

  WorkerArgs = object
    queue: ptr Queue
    resultsLock: ptr Lock
    results: ptr seq[TestResult]
    resultsDir: string
    quiet: bool
    failFast: bool
    activeCount: ptr int

proc ensureDir(dir: string) =
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)

proc looksLikeTestStem(stem: string): bool =
  ## Heuristic for "this binary is a test edge". Matches the file
  ## conventions of reprobuild's M1 generator (``t_*`` and ``test_*``
  ## file basenames lower-cased onto disk).
  stem.startsWith("t_") or stem.startsWith("test_")

proc scanTestBinaries(binDir: string): seq[string] =
  result = @[]
  if not dirExists(binDir):
    return
  for kind, path in walkDir(binDir):
    if kind != pcFile:
      continue
    let stem = splitFile(path).name
    if not looksLikeTestStem(stem):
      continue
    if stem in ExcludeStems:
      continue
    when defined(windows):
      if not path.endsWith(".exe"):
        continue
    else:
      let info = getFileInfo(path)
      if fpUserExec notin info.permissions:
        continue
    result.add(path.absolutePath)
  result.sort()

proc looksProtocolAwareByStrings(binary: string): bool =
  ## Cheap text-scan over the binary: a binary is protocol-aware iff it
  ## links the ``ct_test_unittest_parallel`` shim, which embeds the
  ## marker string "ct_test_unittest_parallel" (the module's own
  ## stderr-prefix literal). This avoids spending a full ``--list-json``
  ## execution on every ``std/unittest`` binary just to discover that
  ## it ignores the flag and runs its whole suite.
  const Marker = "ct_test_unittest_parallel"
  const ChunkSize = 64 * 1024
  try:
    let f = open(binary, fmRead)
    defer: f.close()
    var carry = ""
    var buf = newString(ChunkSize)
    while true:
      let n = f.readBuffer(addr buf[0], ChunkSize)
      if n <= 0:
        break
      let chunk = carry & buf[0 ..< n]
      if chunk.contains(Marker):
        return true
      # Keep the last len(Marker)-1 bytes so the marker isn't split
      # across chunk boundaries.
      if chunk.len > Marker.len - 1:
        carry = chunk[chunk.len - Marker.len + 1 .. ^1]
      else:
        carry = chunk
    return false
  except CatchableError:
    return false

proc probeBinary(binary: string): tuple[protocol: bool;
                                        catalog: seq[(string, string)]] =
  ## Decide whether the binary speaks the protocol and return its test
  ## catalog when so. Two stages: (1) cheap byte-scan for the
  ## ``ct_test_unittest_parallel`` marker — if absent, the binary is
  ## treated as opaque without running it. (2) when the marker is
  ## present, invoke ``--list-json`` and parse the JSON catalog.
  result.protocol = false
  result.catalog = @[]
  if not looksProtocolAwareByStrings(binary):
    return
  let (output, exitCode) = execCmdEx(quoteShell(binary) & " --list-json")
  if exitCode != 0:
    return
  let trimmed = output.strip()
  if trimmed.len == 0 or trimmed[0] != '{':
    return
  try:
    let doc = parseJson(trimmed)
    if not doc.hasKey("tests") or doc["tests"].kind != JArray:
      return
    var cat: seq[(string, string)] = @[]
    for entry in doc["tests"]:
      let suite = entry{"suite"}.getStr("")
      let name = entry{"name"}.getStr("")
      # ``name`` in the JSON catalog is the qualified form
      # ``suite::test``. Extract the bare test name for the registry.
      var bareName = name
      if name.startsWith(suite & "::"):
        bareName = name[len(suite) + 2 .. ^1]
      cat.add((suite, bareName))
    result.protocol = true
    result.catalog = cat
  except JsonParsingError:
    return

proc qualifyName(binaryStem, suite, name: string): string =
  if suite.len > 0:
    suite & "::" & name
  else:
    name

proc runWholeBinary(tc: TestCase; resultsDir: string): TestResult =
  result.testCase = tc
  result.status = tsFail
  let t0 = epochTime()
  let (output, exitCode) = execCmdEx(quoteShell(tc.binary))
  result.durationMs = int((epochTime() - t0) * 1000)
  result.stdout = output
  result.stderr = ""
  case exitCode
  of 0: result.status = tsPass
  of 2: result.status = tsSkip
  else: result.status = tsFail

proc runOneProtocol(tc: TestCase; resultsDir: string): TestResult =
  result.testCase = tc
  result.status = tsFail
  let resultFile = resultsDir / (tc.binaryStem & "__" &
    tc.qualifiedName.multiReplace([
      ("::", "__"), ("/", "_"), (" ", "_"), ("\t", "_")]) & ".json")
  result.resultFile = resultFile
  putEnv("NIMTEST_RESULT_FILE", resultFile)
  let t0 = epochTime()
  let (output, exitCode) = execCmdEx(
    quoteShell(tc.binary) & " --run " &
    quoteShell(tc.qualifiedName))
  result.durationMs = int((epochTime() - t0) * 1000)
  result.stdout = output
  case exitCode
  of 0: result.status = tsPass
  of 2: result.status = tsSkip
  else: result.status = tsFail
  # Prefer the duration_ms recorded in the result file when present.
  if fileExists(resultFile):
    try:
      let doc = parseJson(readFile(resultFile))
      if doc.hasKey("duration_ms"):
        result.durationMs = doc["duration_ms"].getInt(result.durationMs)
    except CatchableError:
      discard

proc nextCase(queue: ptr Queue; failFast: bool;
              out_case: var TestCase): bool =
  acquire(queue.lock)
  defer: release(queue.lock)
  if failFast and queue.failFastTriggered:
    return false
  if queue.pos >= queue.items.len:
    return false
  out_case = queue.items[queue.pos]
  inc queue.pos
  return true

proc markFailFast(queue: ptr Queue) =
  acquire(queue.lock)
  queue.failFastTriggered = true
  release(queue.lock)

proc emitProgress(quiet: bool; res: TestResult) =
  if quiet:
    return
  let label = "[" & $res.status & "]"
  let name =
    if res.testCase.protocolAware:
      res.testCase.binaryStem & " " & res.testCase.qualifiedName
    else:
      res.testCase.binaryStem & " (whole-binary)"
  stderr.writeLine label & " " & name & " (" & $res.durationMs & "ms)"

proc workerLoop(args: WorkerArgs) =
  while true:
    var tc: TestCase
    if not nextCase(args.queue, args.failFast, tc):
      break
    discard atomicInc(args.activeCount[])
    var res: TestResult
    if tc.protocolAware:
      res = runOneProtocol(tc, args.resultsDir)
    else:
      res = runWholeBinary(tc, args.resultsDir)
    discard atomicDec(args.activeCount[])

    acquire(args.resultsLock[])
    args.results[].add(res)
    release(args.resultsLock[])

    emitProgress(args.quiet, res)
    if args.failFast and res.status == tsFail:
      markFailFast(args.queue)

proc writeSummary(summaryPath: string; results: seq[TestResult];
                  wallTimeMs: int; threadsUsed: int;
                  catalogTotal: int; skippedByPartition: int) =
  var executed = results.len
  var passed = 0
  var failed = 0
  var skipped = 0
  var arr = newJArray()
  for r in results:
    case r.status
    of tsPass: inc passed
    of tsFail: inc failed
    of tsSkip: inc skipped
    var node = newJObject()
    node["binary"] = %r.testCase.binary
    node["binary_stem"] = %r.testCase.binaryStem
    node["protocol_aware"] = %r.testCase.protocolAware
    node["qualified_name"] = %r.testCase.qualifiedName
    node["status"] = %($r.status)
    node["duration_ms"] = %r.durationMs
    node["result_file"] = %r.resultFile
    arr.add(node)
  var doc = newJObject()
  var summary = newJObject()
  # ``total`` is the catalog-wide test count (count of tests the runner
  # discovered across all binaries before partition filtering);
  # ``executed`` is the number that actually ran. With no partition
  # filter, total == executed.
  summary["total"] = %catalogTotal
  summary["executed"] = %executed
  summary["passed"] = %passed
  summary["failed"] = %failed
  summary["skipped"] = %skipped
  summary["skipped_by_partition"] = %skippedByPartition
  summary["wall_time_ms"] = %wallTimeMs
  summary["threads"] = %threadsUsed
  doc["summary"] = summary
  doc["tests"] = arr
  ensureDir(parentDir(summaryPath))
  writeFile(summaryPath, doc.pretty())

# ---- partition support ----------------------------------------------

type
  PartitionMode = enum
    pmNone
    pmFile

  PartitionSpec = object
    mode: PartitionMode
    allowed: HashSet[string]   ## allowed fully-qualified test names

proc parsePartitionFile(path: string): HashSet[string] =
  ## Parse a custom partition file. Format: one fully-qualified test
  ## name per line; ``#`` introduces a comment; blank lines are
  ## ignored. (Per codetracer-specs Nim-Parallel-Test-Framework.md
  ## §15.1.)
  result = initHashSet[string]()
  for raw in readFile(path).splitLines():
    var line = raw
    let hashIdx = line.find('#')
    if hashIdx >= 0:
      line = line[0 ..< hashIdx]
    line = line.strip()
    if line.len == 0:
      continue
    result.incl(line)

proc parsePartition(arg: string): PartitionSpec =
  ## Parse a ``--partition`` argument value.  Only ``file:<path>`` is
  ## implemented in M4. ``slice:`` and ``hash:`` exit 2 with a pointer
  ## to the canonical spec.
  if arg.startsWith("file:"):
    let path = arg["file:".len .. ^1]
    if path.len == 0:
      stderr.writeLine "ct-test-runner: --partition file: requires a path"
      quit(2)
    if not fileExists(path):
      stderr.writeLine "ct-test-runner: partition file not found: " & path
      quit(2)
    result.mode = pmFile
    result.allowed = parsePartitionFile(path)
  elif arg.startsWith("slice:") or arg.startsWith("hash:"):
    stderr.writeLine "ct-test-runner: --partition " &
      arg.split(':')[0] & ": not implemented in this runner."
    stderr.writeLine "  See codetracer-specs/Planned-Features/" &
      "Nim-Parallel-Test-Framework.md §15.1 for the canonical spec."
    stderr.writeLine "  Only --partition file:<path> is supported here;"
    stderr.writeLine "  slice/hash sharding belongs to the upstream " &
      "ct-test-runner."
    quit(2)
  else:
    stderr.writeLine "ct-test-runner: unrecognised --partition spec: " & arg
    stderr.writeLine "  expected: file:<path>"
    quit(2)

# ---- main ------------------------------------------------------------

type
  RunnerOpts = object
    binDir: string
    threads: int
    summaryPath: string
    quiet: bool
    filters: seq[string]
    resultsDir: string
    partition: PartitionSpec
    positionalBinaries: seq[string]

proc defaultThreads(): int =
  let env = getEnv("REPRO_TEST_THREADS")
  if env.len > 0:
    try: return parseInt(env)
    except ValueError: discard
  let np = getEnv("NPROC")
  if np.len > 0:
    try: return parseInt(np)
    except ValueError: discard
  result = countProcessors()
  if result <= 0:
    result = 1

proc parseArgs(): RunnerOpts =
  result.binDir = DefaultBinDir
  result.threads = defaultThreads()
  result.summaryPath = DefaultSummaryPath
  result.quiet = false
  result.filters = @[]
  result.resultsDir = DefaultResultsSubdir
  result.partition = PartitionSpec(mode: pmNone,
                                   allowed: initHashSet[string]())
  result.positionalBinaries = @[]

  # Strip a leading ``run`` subcommand if present. The codetracer spec
  # uses ``ct-test-runner run ...``; the M3 runner had no subcommand.
  # We accept both.
  var rawArgs = commandLineParams()
  if rawArgs.len > 0 and rawArgs[0] == "run":
    rawArgs.delete(0)

  var p = initOptParser(rawArgs)
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "threads", "j": result.threads = parseInt(p.val)
      of "bin-dir": result.binDir = p.val
      of "build", "no-build":
        # M3-compat. ct-test-runner does not drive the build; the
        # caller (Justfile / run_tests.sh) is responsible for that.
        discard
      of "summary-json": result.summaryPath = p.val
      of "results-dir": result.resultsDir = p.val
      of "quiet": result.quiet = true
      of "filter": result.filters.add(p.val)
      of "partition": result.partition = parsePartition(p.val)
      of "help", "h":
        echo "ct-test-runner — protocol-level parallel test runner"
        echo "Usage: ct-test-runner [run] [OPTIONS] [BINARY...]"
        echo ""
        echo "  --threads N         worker count (default $NPROC)"
        echo "  --bin-dir DIR       scan DIR for test binaries when no"
        echo "                      positional BINARYs are passed"
        echo "  --partition SPEC    file:<path>  (slice:/hash: unsupported)"
        echo "  --summary-json P    write per-run JSON summary to P"
        echo "  --results-dir DIR   per-test JSON result file dir"
        echo "  --filter SUBSTR     only run binaries whose stem matches"
        echo "  --quiet             suppress per-test progress lines"
        echo ""
        echo "  REPRO_TEST_FAIL_FAST=1   stop scheduling after first FAIL"
        echo "  REPRO_TEST_THREADS=N     override default worker count"
        quit(0)
      else:
        stderr.writeLine "ct-test-runner: unknown option --" & p.key
        quit(2)
    of cmdArgument:
      # Treat as a positional test-binary path.
      result.positionalBinaries.add(p.key.absolutePath)
  if result.threads <= 0:
    result.threads = 1

proc matchesFilter(stem: string; filters: seq[string]): bool =
  if filters.len == 0:
    return true
  for f in filters:
    if f.len > 0 and stem.contains(f):
      return true
  false

# Worker threads need plain pointers, not closures, so we use a top-
# level thread proc that receives a ``WorkerArgs`` value.
proc workerMain(args: WorkerArgs) {.thread.} =
  workerLoop(args)

proc main() =
  let opts = parseArgs()

  # Discovery: positional binaries take precedence; otherwise scan
  # ``--bin-dir``.
  var binaries: seq[string]
  if opts.positionalBinaries.len > 0:
    binaries = opts.positionalBinaries
    binaries.sort()
  else:
    binaries = scanTestBinaries(opts.binDir)

  if binaries.len == 0:
    stderr.writeLine "ct-test-runner: no test binaries found under " &
      opts.binDir
    quit(1)

  ensureDir(opts.resultsDir)

  # Build the work queue: one TestCase per protocol test, or one
  # whole-binary TestCase per non-protocol binary.
  var filteredBinaries: seq[string] = @[]
  for binary in binaries:
    let stem = splitFile(binary).name
    if matchesFilter(stem, opts.filters):
      filteredBinaries.add(binary)
  stderr.writeLine "ct-test-runner: probing " &
    $filteredBinaries.len & " of " & $binaries.len & " binaries"
  var queue = Queue(items: @[])
  initLock(queue.lock)
  var protocolBinaries = 0
  var opaqueBinaries = 0
  var catalogTotal = 0          ## tests discovered across all binaries
  var skippedByPartition = 0    ## tests dropped by --partition file:
  var partitionMatched = initHashSet[string]()
  for binary in binaries:
    let stem = splitFile(binary).name
    if not matchesFilter(stem, opts.filters):
      continue
    let probe = probeBinary(binary)
    if probe.protocol:
      inc protocolBinaries
      for (suite, name) in probe.catalog:
        let qname = qualifyName(stem, suite, name)
        inc catalogTotal
        if opts.partition.mode == pmFile and
            qname notin opts.partition.allowed:
          inc skippedByPartition
          continue
        if opts.partition.mode == pmFile:
          partitionMatched.incl(qname)
        var tc = TestCase(
          binary: binary,
          binaryStem: stem,
          protocolAware: true,
          suite: suite,
          name: name,
          qualifiedName: qname)
        queue.items.add(tc)
    else:
      inc opaqueBinaries
      inc catalogTotal
      let qname = stem
      if opts.partition.mode == pmFile and
          qname notin opts.partition.allowed:
        inc skippedByPartition
        continue
      if opts.partition.mode == pmFile:
        partitionMatched.incl(qname)
      var tc = TestCase(
        binary: binary,
        binaryStem: stem,
        protocolAware: false,
        suite: "",
        name: stem,
        qualifiedName: stem)
      queue.items.add(tc)

  # Partition diagnostics: warn once about names listed in the
  # partition file that didn't appear in any binary's catalog.
  if opts.partition.mode == pmFile:
    var missing: seq[string] = @[]
    for name in opts.partition.allowed:
      if name notin partitionMatched:
        missing.add(name)
    if missing.len > 0:
      missing.sort()
      stderr.writeLine "ct-test-runner: warning: " & $missing.len &
        " name(s) in partition file not found in any binary:"
      for name in missing:
        stderr.writeLine "  " & name

  stderr.writeLine "ct-test-runner: " & $protocolBinaries &
    " protocol-aware, " & $opaqueBinaries & " whole-binary, " &
    $queue.items.len & " test cases queued (" & $catalogTotal &
    " discovered, " & $skippedByPartition & " skipped by partition), " &
    $opts.threads & " threads"

  var resultsLock: Lock
  initLock(resultsLock)
  var results: seq[TestResult] = @[]
  var activeCount: int = 0
  let failFast = getEnv("REPRO_TEST_FAIL_FAST") == "1"

  let args = WorkerArgs(
    queue: addr queue,
    resultsLock: addr resultsLock,
    results: addr results,
    resultsDir: opts.resultsDir,
    quiet: opts.quiet,
    failFast: failFast,
    activeCount: addr activeCount)

  let nThreads = min(opts.threads, max(1, queue.items.len))
  var threads = newSeq[Thread[WorkerArgs]](nThreads)
  let wallT0 = epochTime()
  if queue.items.len > 0:
    for i in 0 ..< nThreads:
      createThread(threads[i], workerMain, args)
    joinThreads(threads)
  let wallMs = int((epochTime() - wallT0) * 1000)

  writeSummary(opts.summaryPath, results, wallMs, nThreads,
               catalogTotal, skippedByPartition)

  var passed = 0
  var failed = 0
  var skipped = 0
  for r in results:
    case r.status
    of tsPass: inc passed
    of tsFail: inc failed
    of tsSkip: inc skipped

  stderr.writeLine "ct-test-runner: ran " & $results.len &
    " cases in " & $wallMs & "ms — pass=" & $passed &
    " fail=" & $failed & " skip=" & $skipped &
    " (summary at " & opts.summaryPath & ")"

  if failed > 0:
    quit(1)
  quit(0)

main()
