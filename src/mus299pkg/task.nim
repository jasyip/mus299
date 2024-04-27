import std/[paths, tempfiles]
import std/strutils
import std/sets
import std/re
import std/streams
import std/sequtils
from std/math import almostEqual

import chronos
import chronos/asyncproc
import stew/byteutils
import results

import core
import performer

const staffPrefixesSet = toHashSet(staffPrefixes)

proc resyncTaskSnippet*(snippet: TaskSnippet; pool: TaskPool): Future[Result[void, string]] {.async.} =

  block:
    let file = openFileStream(string(snippet.path / "source.ly".Path), fmWrite)
    defer: file.close()
    file.write(pool.sourceTemplate)
  
    file.write:
      # assume that snippet is already whitespace-stripped
      if "\p" in snippet.snippet:
        snippet.snippet
      else:
        var matches: array[1, string]
        if contains(snippet.snippet, pool.isAssignment, matches):
          if matches[0] != pool.varName:
            pool.varName & snippet.snippet[matches[0].len .. ^1]
          else:
            raise ValueError.newException("Unparseable")
        else:
          pool.varName & " = " & (if contains(snippet.snippet, pool.isExpression): snippet.snippet
                             else: (if snippet.staffPrefix == "Drum": r"\drums "
                                    else: "") & "{" & snippet.snippet & "}")
  
    let taskExpr = (if pool.timeSig == "": ""
                    else: r"\time " & pool.timeSig & " "
                   ) & r"\task"
  
    for i, performer in pool.performers.pairs:
      if (performer.instrument.staffPrefix == "Drum") != (snippet.staffPrefix == "Drum"):
        continue

      file.write("\p")
      if i > 0:
        file.write("\p")
  
      const newLine = "\p" & repeat(' ', 6)
  
      var propertiesExpr, specificTaskExpr = ""
  
      if not almostEqual(performer.minVolume, 0.0):
        propertiesExpr.add("midiMinimumVolume = #" &
                           formatFloat(performer.minVolume, ffDecimal, 2) &
                           newLine
                          )
      if not almostEqual(performer.maxVolume, 1.0):
        propertiesExpr.add("midiMaximumVolume = #" &
                           formatFloat(performer.maxVolume, ffDecimal, 2) &
                           newLine
                          )
  
      if performer.clef != "":
        specificTaskExpr.add(r"\clef " & performer.clef & newLine)
      if snippet.staffPrefix != "Drum" and performer.key != "":
        specificTaskExpr.add(r"\key " & performer.key & newLine)
        specificTaskExpr.add(r"\transpose " & snippet.key & " " & transposeKey(performer[]) & " ")
      file.write(format($pool.staffTemplate,
        "instrumentName", performer.name,
        "midiInstrument", performer.instrument.name,
        "staffPrefix", snippet.staffPrefix,
        "tempo", (if pool.tempo == "": "" else: r"\tempo " & pool.tempo),
        "properties", propertiesExpr,
        "task", specificTaskExpr & taskExpr,
      ))

  const args = @["-lERROR", "--svg", "-dno-print-pages", "-dcrop", "source.ly"]
  let p = await startProcess("lilypond",
                             snippet.path.string,
                             args,
                             options = {UsePath},
                             stderrHandle = AsyncProcess.Pipe,
                            )
  let (code, msg) = try:
    let
      stderrFut = p.stderrStream.read()
      codeFut = p.waitForExit()

    if not await codeFut.withTimeout(3.seconds):
      codeFut.cancelSoon()
      return err("lilypond process took too long or the infamous bug with chronos that can't reap zombies properly is occuring")
    (codeFut.read(), string.fromBytes(await stderrFut))
  finally:
    await p.closeWait()

  if code == 0:
    ok()
  else:
    err(msg)


proc newTaskSnippet*(pool: TaskPool; snippet: string; name = ""; key = "c"; staffPrefix = ""): Future[Result[TaskSnippet, string]] {.async.} =
  if staffPrefix notin staffPrefixesSet:
    raise ValueError.newException("unsupported staff prefix")
  let snippet = TaskSnippet(path: createTempDir("mus299-", "").Path, snippet: snippet, name: name, key: key, staffPrefix: staffPrefix)
  (await resyncTaskSnippet(snippet, pool)) and ok(snippet)


func changeDependencies*(task: Task; newDepends: HashSet[Task]) =
  template e: auto = ValueError.newException("task dependency cycle detected")
  if task in newDepends:
    raise e()
  var
    acyclic: HashSet[Task]
    stack = toSeq(newDepends - task.depends)

  while stack.len > 0:
    let cur = stack.pop()
    if cur notin acyclic:
      acyclic.incl(cur)
      for v in cur.depends.items:
        if v == task:
          raise e()
        if v notin acyclic:
          stack.add(v)

  for i in items(task.depends - newDepends):
    i.dependents.excl(task)

  for i in items(newDepends - task.depends):
    i.dependents.incl(task)

  task.depends = newDepends


template newTask*(snippet: TaskSnippet; args: varargs[typed]): Task =
  result = Task(snippet: snippet, args)

  for parent in result.depends:
    parent.dependents.incl(result)
