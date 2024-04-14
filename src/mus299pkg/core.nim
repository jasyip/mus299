import std/[paths, dirs]

import std/[hashes, sets]
import std/tables


import chronos





{.experimental: "notnil".}

type

  Category* = distinct string

  # Duplicate tasks refer to the same object. The only mutable
  # attribute should be `performers`
  Task* = ref TaskObj
  TaskSnippet* = ref TaskSnippetObj
  TaskObj* = object
    snippet*: TaskSnippet
    depends*, dependents*: HashSet[Task]
    readyDepends*: uint = 0
    allowedCategories*: HashSet[Category]
    performers*: OrderedSet[Performer]
  TaskSnippetObj* = object
    path*: Path
    snippet*: string
    key* = "c"

  Performer* = ref PerformerObj
  # Duplicate performers are their own object
  PerformerObj* = object of RootObj
    performing* = false
    # When performing, the size of this should be just 1
    # but when that task requires another task at a certain time,
    # the sequence can be appended to with the "secondary" task(s)
    categories*: HashSet[Category]
    name*: string
    instrument*: Instrument
    minVolume* = 0.0
    maxVolume* = 1.0
    key*, clef* = ""

  Instrument* = ref InstrumentObj not nil
  InstrumentObj = object
    name*: string
    staffPrefix*: string
    semitoneTranspose*: range[-127..127]


  TaskPool* = ref TaskPoolObj not nil
  TaskPoolObj* = object
    performers*: OrderedSet[Performer]
    getters*: Table[Category, HashSet[Future[void].Raising([CancelledError])]]
    pool*: Table[Category, HashSet[Task]]
    toReincarnate*: Table[Performer, Task]
    tempo*, timeSig* = ""


func hash*(_: Category): Hash {.borrow.}
func `==`*(_, _: Category): bool {.borrow.}



proc `=destroy`*(x: TaskSnippetObj) =
  if x.path.string.len > 0:
    try:
      removeDir(x.path)
    except OSError:
      discard

  for f in x.fields:
    `=destroy`(f.addr[])
