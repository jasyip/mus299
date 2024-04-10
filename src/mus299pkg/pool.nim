import std/[sets, tables]
import std/random
from std/sugar import collect
import std/enumerate
import std/options

import chronos

import core

#[
proc dec[A](t: var CountTable[A]; key: A; val = 1) =
  if val > 0:
    assert t.getOrDefault(key) >= val
  t.inc(key, -val)

proc replaceTasks(pool: TaskPool; oldTask, newTask: Task): int =
  if pool.availableTasks.pop(oldTask, result):
    pool.availableTasks.inc(newTask, result)

proc addTask*(pool: TaskPool; task: Task; val: uint = 1) =
  var
    remainingCopies = val
    availableCategories: seq[ptr seq[Future[Task]]]

  for category in task.allowedCategories.items:
    if category in pool.futures:
      availableCategories.add(pool.futures[category].addr)

  while remainingCopies > 0 and availableCategories.len > 0:
    let
      chosenCategoryInd = rand(availableCategories.len - 1)
      chosenCategory = availableCategories[chosenCategoryInd]
      chosenInd = rand(chosenCategory[].len - 1)

    swap(chosenCategory[][chosenInd], chosenCategory[][^1])

    chosenCategory[].pop().complete(task)
    if chosenCategory[].len == 0:
      swap(availableCategories[chosenCategoryInd], availableCategories[^1])
      discard availableCategories.pop()
    dec(remainingCopies)

  pool.availableTasks.inc(task, remainingCopies.int)



proc popTask*(pool: TaskPool; categories: SomeSet[Category]): Future[Task] {.async: (raw: true).} =
  result = newFuture[Task]("popTask")
  try:
    let isAcceptable = (
        if categories.len > 0: (proc (task: Task): bool =
                                not task.allowedCategories.disjoint(categories))
        else: (proc (_: Task): bool = true))

    for task in pool.availableTasks.keys:
      if isAcceptable(task):
        result.complete(task)
        pool.availableTasks.dec(task)
        return

    # no acceptable tasks
    for category in categories.items:
      pool.futures.mgetOrPut(category, newSeq[Future[Task]]()).add(result)

  except CatchableError as e:
    result.fail(e)


func validPerformers*(pool: TaskPool, task: Task): seq[Performer] =
  for performer in pool.performers.items:
    if not performer.categories.disjoint(task.allowedCategories):
      result.add(performer)
]#

proc randomItem[T](pool: var Table[Category, HashSet[T]];
                   categories: HashSet[Category];
                   delete: proc(x: T): bool {.noSideEffect, closure, raises: [].} = nil
                  ): Option[T] {.raises: [].} =

  var possible: HashSet[T]
  for category in categories.items:
    pool.withValue(category, entry):
      if not delete.isNil():
        let toDelete = collect:
          for item in entry[].items:
            if delete(item):
              item
        for item in toDelete:
          entry[].excl(item)
        if entry[].len == 0:
          pool.del(category)
          continue

      possible.incl(entry[])

  if possible.len > 0:
    let chosen = rand(possible.len - 1)
    for i, item in enumerate(possible.items):
      if i == chosen:
        return item.some()
  else:
    return none(T)


proc wakeupNext(pool: TaskPool; categories: HashSet[Category]) {.raises: [].} =
  let chosenWaiter = randomItem(pool.getters, categories) do (x: Future[void].Raising([CancelledError])) -> bool:
    x.finished()

  chosenWaiter.map do (x: auto):
    x.complete()


proc addTask*(pool: TaskPool; task: Task) =
  for category in task.allowedCategories.items:
    pool.pool.mgetOrPut(category, HashSet[Task].default).incl(task)
  pool.wakeupNext(task.allowedCategories)

proc popTask*(pool: TaskPool; categories: HashSet[Category]): Future[Task] {.async: (raises: [CancelledError]).} =

  while true:

    let chosenTask = randomItem(pool.pool, categories)
    if chosenTask.isSome:
      result = chosenTask.unsafeGet
      break

    let getter = Future[void].Raising([CancelledError]).init("TaskPool.addTask")
    for category in categories.items:
      pool.getters.mgetOrPut(category, HashSet[Future[void].Raising([CancelledError])].default).incl(getter)

    try:
      await getter
    except CancelledError as exc:
      if not getter.cancelled():
        pool.wakeupNext(categories)
      raise exc

  for category in result.allowedCategories:
    var taskSet: ptr HashSet[Task]
    try:
      taskSet = pool.pool[category].addr
    except KeyError:
      raiseAssert getCurrentExceptionMsg()
    if taskSet[].len == 1:
      pool.pool.del(category)
    else:
      taskSet[].excl(result)
