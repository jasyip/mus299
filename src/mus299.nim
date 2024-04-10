import mus299pkg/[core, task, pool, performer]
import std/appdirs
import std/re
import std/paths
import std/sets
import std/strutils
import std/random

import chronos



const
  staffJoinStr = "\p"
  varName = "task"
  expressionRe = r"\s*(?:\\\w+\s*)*\{" 

  dataDir = getDataDir() / "mus299".Path

  player = "aplaymidi"
  playerParams = @["-p", "128", "-d", "0"]

# TODO: start fluidsynth daemon and stop for convenience if asked


proc main {.async.} =

  randomize()

  let
    isExpression = re(r"^" & expressionRe, {reIgnoreCase, reMultiLine, reStudy})
    isAssignment = re(r"^([a-z]+)\s*=" & expressionRe, {reMultiLine, reStudy})
    sourceTemplate = readFile(string(dataDir / "template.ly".Path))
    staffTemplate = readFile(string(dataDir / "staff.ly".Path))

    brass = toHashSet(["Brass".Category])
    instrument = newInstrument("acoustic grand", "", 0)

  var
    pool = TaskPool()
    performer = Performer(categories: brass, name: "Trumpet", instrument: instrument)
  pool.performers.incl(performer)
  var
    task1 = Task(snippet: (await newTaskSnippet("a' b' c'' d''", pool, isExpression, isAssignment, staffJoinStr, varName, sourceTemplate, staffTemplate)), allowedCategories: brass)
    task2 = Task(snippet: (await newTaskSnippet("a b c' d'", pool, isExpression, isAssignment, staffJoinStr, varName, sourceTemplate, staffTemplate)), allowedCategories: brass)
    task3, task4 = new(Task)

  task3[] = task1[]
  task4[] = task2[]
  pool.addTask(task1)
  pool.addTask(task3)
  pool.addTask(task2)
  pool.addTask(task4)
  for i in 0..<4:
    await performer.perform(pool, player, playerParams) do (x: Task):
      echo x.repr
  
when isMainModule:
  waitFor main()
