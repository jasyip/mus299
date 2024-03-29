import core
import pool

import chronos

import std/[sets, tables]
import std/sequtils

proc dec[A](t: var CountTable[A]; key: A; val = 1) =
  if val > 0:
    assert t.getOrDefault(key) >= val
  t.inc(key, -val)

proc performTask*(performer: var PerformerObj; task: Task; pool: var TaskPool) {.async.} =
  assert performer.state != Performing
  assert anyIt({
      performer.categories: false,
      task.allowedCategories: false,
      performer.categories * task.allowedCategories: true,
      }, (it[0].len > 0) == it[1])
  performer.state = Performing
  performer.currentTasks.add(task)
  pool.availableTasks.dec(task)

  # Do performing here

proc fetchTask*(performer: var PerformerObj; pool: var TaskPool): Future[Task] {.async.} =
  let task = await pool.popTask(performer.categories)
