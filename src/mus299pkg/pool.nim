import std/[sets, tables]
import std/random
from std/sugar import collect
import std/enumerate
import std/sequtils
import std/strformat

import chronos
import chronos/asyncproc

import core


func wouldWait[T](pool: var Table[Category, HashSet[T]];
                  categories: HashSet[Category];
                  delete: proc(x: T): bool {.noSideEffect, raises: [].} = nil
                 ): bool {.raises: [].} =
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

      if entry[].len > 0:
        return false

  true


proc randomItem[T](pool: var Table[Category, HashSet[T]];
                   categories: HashSet[Category];
                  ): T {.raises: [].} =

  var possible: HashSet[T]
  for category in categories.items:
    pool.withValue(category, entry):
      possible.incl(entry[])

  let chosen = rand(possible.len - 1)
  for i, item in enumerate(possible.items):
    if i == chosen:
      return item


proc wakeupNext(pool: TaskPool; categories: HashSet[Category]) {.raises: [].} =
  if not (wouldWait(pool.getters, categories) do (x: Future[void].Raising([CancelledError])) -> bool:
            x.finished()
         ):
    randomItem(pool.getters, categories).complete()


proc addTask*(pool: TaskPool; task: Task) =
  task.readyDepends = task.depends.len.uint
  for category in task.allowedCategories.items:
    pool.pool.mgetOrPut(category, HashSet[Task].default).incl(task)
  pool.wakeupNext(task.allowedCategories)

proc popTask*(pool: TaskPool;
              categories: HashSet[Category];
              performer: Performer
             ): Future[Task] {.async: (raises: [CancelledError]).} =

  proc reincarnate =
    pool.toReincarnate.withValue(performer, entry):
      for t in entry[].dependents.items:
        t.readyDepends.inc
        if t.readyDepends == t.depends.len.uint:
          pool.addTask(t)
      pool.toReincarnate.del(performer)


  if wouldWait(pool.pool, categories):

    let getter = Future[void].Raising([CancelledError]).init("TaskPool.popTask")
    for category in categories.items:
      pool.getters.mgetOrPut(category,
                             HashSet[Future[void].Raising([CancelledError])].default
                            ).incl(getter)

    reincarnate()

    try:
      await getter
    except CancelledError as exc:
      if not getter.cancelled():
        pool.wakeupNext(categories)
      raise exc
  else:
    reincarnate()

  result = randomItem(pool.pool, categories)
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


proc resetTaskPool*(pool: TaskPool; starting: HashSet[Task]) =
  pool.pool.clear()
  pool.toReincarnate.clear()
  var stack: seq[Task]
  for task in starting.items:
    task.readyDepends = 0
    for t in task.dependents.items:
      stack.add(t)

  while stack.len > 0:
    let cur = stack.pop()
    if cur.readyDepends > 0:
      cur.readyDepends = 0
      for t in cur.dependents.items:
        stack.add(t)

  for task in starting.items:
    pool.addTask(task)

proc perform(performer: Performer; pool: TaskPool;
             player: string; playerParams: seq[string];
             beforePop: proc() {.gcsafe, raises: [].} = (proc = discard);
             afterPop: proc(x: Task) {.gcsafe, raises: [].} = (proc (_: Task) =
                                                                 discard
                                                              );
            ) {.async: (raises: [CancelledError, AsyncProcessError]).} =
  assert not performer.performing
  let task = await pool.popTask(performer.categories, performer)
  afterPop(task)

  performer.performing = true
  block:
    let playerProc = await startProcess(player, task.snippet.path.string,
                                        concat(playerParams,
                                               @["source-" & performer.name & ".midi"]
                                              ),
                                        options = {UsePath}
                                       )
    defer: await playerProc.closeWait()
    let code = await playerProc.waitForExit()
    if code != 0:
      try:
        raise AsyncProcessError.newException(&"MIDI player return code was {code}")
      except ValueError:
        discard

  performer.performing = false


proc startPerformance*(pool: TaskPool;
                       player: string; playerParams: seq[string];
                       beforePop: proc() {.gcsafe, raises: []} = (proc = discard);
                       afterPop: proc(x: Task) {.gcsafe, raises: [].} = (proc(x: Task) = discard);
                      ) =
  pool.performances.delete(0..<(pool.performances.len))
  for performer in pool.performers.items:
    pool.performances.add(performer.perform(pool, player, playerParams, beforePop, afterPop))
    asyncSpawn pool.performances[^1]

proc endPerformance*(pool: TaskPool) {.async.} =
  for performer in pool.performances:
    performer.cancelSoon()

  await allFutures(pool.performances)

