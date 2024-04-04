import std/rationals

import std/[paths, dirs]

import std/[hashes, sets, tables]
import fusion/btreetables as btrees

import std/locks


import chronos

type
  PerformerState* = enum
    Ready
    Performing
    Blocking

# OrderedSet is used so that it is easier to visualize the management
# of categories on the frontend

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
    # Key is `Rational`, indicating that another task of the value category
    # should be played at this metric position. The performer should be blocked
    # until such a task can be retrieved
    children*: btrees.Table[Hash, HashSet[Category]]
  TaskSnippetObj* = distinct Path

  # Only one exists
  TaskCopy* = ref object
    lock*: Lock
    task*: Task

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
    staffPrefix*: string
    semitoneTranspose*: int


  TaskPool* = object
    availableTasks*: tables.CountTable[Task]
    performers*: OrderedSet[Performer]
    futures*: tables.Table[Category, HashSet[Future[Task]]]

proc `=destroy`*(x: TaskSnippetObj) =
  if x.string.len > 0:
    try:
      removeDir(x.Path)
    except OSError:
      discard

  `=destroy`(x.string)
