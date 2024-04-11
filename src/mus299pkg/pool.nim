import std/[sets, tables]
import std/random
from std/sugar import collect
import std/enumerate
import std/options

import chronos

import core


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

proc popTask*(pool: TaskPool; categories: HashSet[Category]; performer: Performer): Future[Task] {.async: (raises: [CancelledError]).} =

  while true:

    let chosenTask = randomItem(pool.pool, categories)
    if chosenTask.isSome:
      result = chosenTask.unsafeGet
      break

    let getter = Future[void].Raising([CancelledError]).init("TaskPool.addTask")
    for category in categories.items:
      pool.getters.mgetOrPut(category, HashSet[Future[void].Raising([CancelledError])].default).incl(getter)

    pool.toReincarnate.withValue(performer, entry):
      for t in entry[].dependents.items:
        t.dependents.excl(entry[])
        pool.addTask(t)

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

  pool.toReincarnate[performer] = result
