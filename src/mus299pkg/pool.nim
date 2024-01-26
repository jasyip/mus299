import std/asyncdispatch
import std/[sets, tables]
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


proc popTask*(pool: var TaskPool; categories: SomeSet[string]): Future[Task] {.async.} =
  let acceptableTask = (if categories.len > 0:
      (proc (task: Task): bool = not task.allowedCategories.disjoint(categories))
      else: (proc (_: Task): bool = true))
  for task in pool.availableTasks.keys:
    if acceptableTask(task):
      pool.availableTasks.dec(task)
      return task

  var newFuture = newFuture[Task]("popTask")
  for category in categories.items:
    pool.futures.mgetOrPut(category, initHashSet[Future[Task]]()).incl(newFuture)

  await newFuture


