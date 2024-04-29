import std/[paths, dirs]
import std/[hashes, sets]
import std/tables
import std/re
from std/strutils import toHex, align, strip
from std/bitops import fastLog2


import chronos
import chronos/asyncproc





type

  Category* = distinct string

  # Duplicate tasks refer to the same object. The only mutable
  # attribute should be `performers`
  Task* = ref TaskObj
  TaskSnippet* = ref TaskSnippetObj
  TaskObj* = object
    snippet*: TaskSnippet
    depends*, dependents*: HashSet[Task]
    readyDepends* = 0
    allowedCategories*: HashSet[Category]
  TaskSnippetObj* = object
    path*: Path
    snippet*, name*: string
    key* = "c"
    staffPrefix* = ""
    channel* = 0u

  Performer* = ref PerformerObj
  # Duplicate performers are their own object
  PerformerObj* = object of RootObj
    performing*: Task = nil
    # When performing, the size of this should be just 1
    # but when that task requires another task at a certain time,
    # the sequence can be appended to with the "secondary" task(s)
    categories*: HashSet[Category]
    name*: string
    instrument*: Instrument
    minVolume* = 0.0
    maxVolume* = 1.0
    key*, clef* = ""

  Instrument* = ref InstrumentObj
  InstrumentObj = object
    name*: string
    staffPrefix*: string

  # PerformFuture = Future[void].Raising([CancelledError, AsyncProcessError])

  TaskPool* = ref TaskPoolObj
  TaskPoolObj* = object
    tasksnippets*: OrderedSet[TaskSnippet]
    tasks*: OrderedSet[Task]
    instruments*: OrderedSet[Instrument]
    performers*: OrderedSet[Performer]
    initialPool*: HashSet[Task]

    performances*: seq[Future[void]]
    getters*: Table[Category, HashSet[Future[void].Raising([CancelledError])]]
    pool*: Table[Category, HashSet[Task]]
    toReincarnate*: Table[Performer, Task]

    tempo*, timeSig* = ""

    nameRe*, isExpression*, isAssignment*: Regex
    varName*, sourceTemplate*, staffTemplate*: string

    resync*: HashSet[TaskSnippet]
    resyncAll* = false

    synchronizing* = false





func hash*(_: Category): Hash {.borrow.}
func `==`*(_, _: Category): bool {.borrow.}






template hexAddr*(x: typed): string =
  "0x" & cast[uint](cast[pointer](x)).toHex.align(BiggestUint.sizeof.fastLog2() div 4, '0')

proc normalizeName*(x: Category | string, nameRe: Regex): string =
  let stripped = cast[string](x).strip()
  if stripped.matchLen(nameRe) != stripped.len:
    raise ValueError.newException("Given name is unacceptable")
  return stripped

when defined(release):
  proc `=destroy`*(x: TaskSnippetObj) =
    if x.path.string.len > 0:
      try:
        removeDir(x.path)
      except OSError:
        discard
  
    for f in x.fields:
      `=destroy`(f.addr[])
