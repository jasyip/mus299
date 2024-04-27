import mus299pkg/[core, task, pool, performer]
import std/appdirs
import std/re
import std/paths
import std/sets
import std/random

import chronos
import results



const
  expressionRe = r"\s*(?:\\\w+\s*)*\{" 

  dataDir = getDataDir() / "mus299".Path

  player = "aplaymidi"
  playerParams = @["-p", "128", "-d", "0"]

# TODO: start fluidsynth daemon and stop for convenience if asked


proc main {.async.} =

  randomize()
  let
    instrument = newInstrument("acoustic grand", "")
    brass = toHashSet(["brass".Category])

  let pool = TaskPool(
                      varName: "task",
                      isExpression: re(r"^" & expressionRe, {reIgnoreCase, reMultiLine, reStudy}),
                      isAssignment: re(r"^([a-z]+)\s*=" & expressionRe, {reMultiLine, reStudy}),
                      sourceTemplate: readFile(string(dataDir / "template.ly".Path)),
                      staffTemplate: readFile(string(dataDir / "staff.ly".Path)),
                      nameRe: re("[a-z0-9]+(_[a-z0-9]+)*[a-z0-9]*", flags = {reIgnoreCase, reStudy}),
                     )
  pool.performers.incl(Performer(categories: brass, name: "Trumpet", instrument: instrument))
  pool.instruments.incl(instrument)
  let
    snippet1 = get(await newTaskSnippet(pool, "a' b' c'' d''"))
    snippet2 = get(await newTaskSnippet(pool, "a b c' d'"))

    task1 = Task(snippet: snippet1, allowedCategories: brass)
    task2 = Task(snippet: snippet2, allowedCategories: brass)
    task3, task4 = new(Task)

  task3[] = task1[]
  task4[] = task2[]
  changeDependencies(task3, toHashSet([task1]))
  changeDependencies(task4, toHashSet([task2]))

  for s in [snippet1, snippet2]: pool.tasksnippets.incl(s)
  for t in [task1, task2, task3, task4]: pool.tasks.incl(t)
  pool.initialPool.incl(toHashSet([task1, task2]))
  await pool.startPerformance(player, playerParams) 


when isMainModule:
  waitFor main()
