import std/[sets, tables]

import chronos


import core

proc dec[A](t: var CountTable[A]; key: A; val = 1) =
  if val > 0:
    assert t.getOrDefault(key) >= val
  t.inc(key, -val)

proc replaceTasks(pool: var TaskPool; oldTask, newTask: Task): int =
  if pool.availableTasks.pop(oldTask, result):
    pool.availableTasks.inc(newTask, result)

proc addTask(pool: var TaskPool; task: Task; val = 1) =
  var completed = false
  for category in task.allowedCategories.items:
    if category in pool.futures:
      completed = true
      for future in pool.futures[category]:
        if not future.finished():
          future.complete(task)
      pool.futures.del(category)

  if not completed:
    pool.availableTasks.inc(task, val)


proc popTask*(pool: var TaskPool; categories: SomeSet[Category]): Future[Task] {.async: (raw: true).} =
  result = newFuture[Task]("popTask")
  try:
    let isAcceptable = (
        if categories.len > 0: (proc (task: Task): bool =
                                not task.allowedCategories.disjoint(categories))
        else: (proc (_: Task): bool = true))

    for task in pool.availableTasks.keys:
      if isAcceptable(task):
        pool.availableTasks.dec(task)
        result.complete(task)
        return

    # no acceptable tasks
    for category in categories.items:
      pool.futures.mgetOrPut(category, HashSet[Future[Task]].default).incl(result)

  except CatchableError as e:
    result.fail(e)
    for category in categories.items:
      try:
        pool.futures[category].excl(result)
      except KeyError:
        discard


func validPerformers*(pool: TaskPool, task: Task): seq[Performer] =
  for performer in pool.performers.items:
    if not performer.categories.disjoint(task.allowedCategories):
      result.add(performer)
