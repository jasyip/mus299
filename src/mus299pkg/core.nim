import std/[paths, dirs]

import std/[hashes, sets, tables]


import chronos






type
  PerformerState* = enum
    Ready
    Performing
    Blocking

type

  Category* = distinct string

  # Duplicate tasks refer to the same object. The only mutable
  # attribute should be `performers`
  Task* = ref TaskObj
  TaskSnippet* = ref TaskSnippetObj
  TaskObj* = object
    snippet*: TaskSnippet
    depends*: HashSet[Task]
    dependents*: HashSet[Task]
    allowedCategories*: HashSet[Category]
    performers*: OrderedSet[Performer]
    # Another task of the value category should be played at the metric position
    # represented by the key. The performer should be blocked until such a task
    # can be retrieved
    children*: Table[Duration, HashSet[Category]]
  TaskSnippetObj* = object
    path*: Path
    snippet*: string

  Performer* = ref PerformerObj
  # Duplicate performers are their own object
  PerformerObj* = object of RootObj
    state*: PerformerState = Ready
    # When performing, the size of this should be just 1
    # but when that task requires another task at a certain time,
    # the sequence can be appended to with the "secondary" task(s)
    currentTasks*: seq[Task]
    categories*: HashSet[Category]
    name*: string
    instrument*: Instrument

  Instrument* = ref object
    name*: string
    staffPrefix*: string
    semitoneTranspose*: range[-127..127]


  TaskPool* = object
    availableTasks*: CountTable[Task]
    performers*: OrderedSet[Performer]
    futures*: Table[Category, HashSet[Future[Task]]]

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
