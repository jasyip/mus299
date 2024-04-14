import std/appdirs
import std/re
import std/paths
import std/sets
import std/random

import chronos
import owlkettle



import mus299pkg/[core, performer, pool, task]




const
  staffJoinStr = "\p"
  varName = "task"
  expressionRe = r"\s*(?:\\\w+\s*)*\{" 

  dataDir = getDataDir() / "mus299".Path

  player = "aplaymidi"
  playerParams = @["-p", "128", "-d", "0"]



viewable App:
  pool: TaskPool
  tasks: OrderedSet[Task]
  isExpression: Regex
  isAssignment: Regex
  sourceTemplate: string
  staffTemplate: string


method view(app: AppState): Widget =
  gui:
    Window:
      title = "Async Perform"
      defaultSize = (1280, 720)



when isMainModule:

  randomize()

  brew(gui(App(
               pool=TaskPool(),
               isExpression=re(r"^" & expressionRe, {reIgnoreCase, reMultiLine, reStudy}),
               isAssignment=re(r"^([a-z]+)\s*=" & expressionRe, {reMultiLine, reStudy}),
               sourceTemplate=readFile(string(dataDir / "template.ly".Path)),
               staffTemplate=readFile(string(dataDir / "staff.ly".Path)),
              )
          )
      )
