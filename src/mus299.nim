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
    task = Task(snippet: (await newTaskSnippet(repeat("a' b' c'' d' ", 30), pool, isExpression, isAssignment, staffJoinStr, varName, sourceTemplate, staffTemplate)), allowedCategories: brass)

  pool.addTask(task)
  await performer.perform(pool, player, playerParams) do (x: Task):
    echo x.repr
  
when isMainModule:
  waitFor main()
