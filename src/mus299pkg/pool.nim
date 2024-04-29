import std/[sets, tables]
import std/random
from std/sugar import collect
import std/enumerate
import std/sequtils
import std/strutils
import std/hashes

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
        if t.readyDepends >= 0:
          t.readyDepends.inc
        if t.readyDepends == t.depends.len.uint:
          pool.addTask(t)
      entry[].readyDepends = -1
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



proc perform(performer: Performer; pool: TaskPool;
             player: string; playerParams: seq[string];
             beforePop: proc(): Future[void] {.gcsafe, raises: [].} = nil;
             afterPop: proc(_: Task): Future[void] {.gcsafe, raises: [].} = nil;
            ) {.async.} =
  while true:
    defer:
      if not beforePop.isNil:
        await beforePop()
    performer.performing = await pool.popTask(performer.categories, performer)
    defer: performer.performing = nil
    if not afterPop.isNil:
      await afterPop(performer.performing)

    let playerProc = await startProcess(player, performer.performing.snippet.path.string,
                                        concat(playerParams,
                                               @["source-" & performer.name.hash.toHex() & ".midi"]
                                              ),
                                        options = {UsePath}
                                       )
    defer: await playerProc.closeWait()
    let code = await playerProc.waitForExit()
    if code != 0:
      raise AsyncProcessError.newException("MIDI player return code was " & $code)


proc startPerformance*(pool: TaskPool;
                      player: string; playerParams: seq[string];
                      beforePop: proc(): Future[void] {.gcsafe, raises: [].} = nil;
                      afterPop: proc(_: Task): Future[void] {.gcsafe, raises: [].} = nil;
                     ) {.async.} =
  for performer in pool.performers.items:
    pool.performances.add(performer.perform(pool, player, playerParams, beforePop, afterPop))

  for task in pool.initialPool:
    task.readyDepends = -1
    for category in task.allowedCategories.items:
      pool.pool.mgetOrPut(category, HashSet[Task].default).incl(task)

  for task in pool.initialPool:
    pool.wakeupNext(task.allowedCategories)

  await allFutures(pool.performances)

proc startPerformance*(pool: TaskPool;
                       player: string; playerParams: seq[string];
                       beforePop: proc() {.gcsafe, raises: [].};
                       afterPop: proc(_: Task) {.gcsafe, raises: [].} = nil;
                      ) {.async.} =
  let
    bp = if beforePop.isNil: nil
         else:
           proc {.async.} = beforePop()
    ap = if afterPop.isNil: nil
         else:
           proc(x: Task) {.async.} = afterPop(x)
  await startPerformance(pool, player, playerParams, bp, ap)



proc endPerformance*(pool: TaskPool) {.async.} =
  for performer in pool.performances:
    performer.cancelSoon()

  try:
    await allFutures(pool.performances)
  except CancelledError:
    discard
  finally:
    pool.performances = @[]
    pool.getters.clear()
    pool.pool.clear()
    pool.toReincarnate.clear()
    for task in pool.tasks:
      task.readyDepends = 0
