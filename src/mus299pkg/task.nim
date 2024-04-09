import std/[paths, tempfiles]
import std/strutils
import std/sets
import std/re
import std/streams
import std/sequtils

import chronos
import chronos/asyncproc

import core



proc resyncTaskSnippet*(snippet: TaskSnippet;
                        pool: TaskPool;
                        isExpression, isAssignment: Regex;
                        staffJoinStr, varName,
                        sourceTemplate, staffTemplate: string;
                       ) {.async.} =
  block:
    let file = openFileStream(string(snippet.path / "source.ly".Path), fmWrite)
    defer: file.close()
    file.write(sourceTemplate)

    file.write:
      # assume that snippet is already whitespace-stripped
      if "\p" in snippet.snippet:
        snippet.snippet
      else:
        var matches: array[1, string]
        if contains(snippet.snippet, isAssignment, matches):
          if matches[0] != varName:
            varName & snippet.snippet[matches[0].len .. ^1]
          else:
            raise ValueError.newException("Unparseable")
        else:
          varName & " = " & (if contains(snippet.snippet, isExpression): snippet.snippet
                             else: "{" & snippet.snippet & "}")


    for i, performer in pool.performers.pairs:
      file.write("\p")
      if i > 0:
        file.write(staffJoinStr)
      file.write(format($staffTemplate,
        "instrumentName", performer.name,
        "midiInstrument", performer.instrument.name,
        "staffPrefix", performer.instrument.staffPrefix,
      ))

  const args = @["--svg", "-s", "source.ly"]
  let p = await startProcess("lilypond", snippet.path.string, args, options={UsePath})
  defer: await p.closeWait()
  if (await p.waitForExit(10 * Second)) != 0:
    raise OSError.newException("lilypond invocation failed")


proc newTaskSnippet*(snippet: string;
                     pool: TaskPool;
                     isExpression, isAssignment: Regex;
                     staffJoinStr, varName,
                     sourceTemplate, staffTemplate: string;
                    ): Future[TaskSnippet] {.async.} =
  result = TaskSnippet(path: createTempDir("mus299", "").Path, snippet: snippet)
  await resyncTaskSnippet(result, pool, isExpression, isAssignment, staffJoinStr, varName, sourceTemplate, staffTemplate)


proc changeDependencies*(task: Task, newDepends: HashSet[Task]) =
  let e = ValueError.newException("task dependency cycle detected")
  if task in newDepends:
    raise e
  var
    acyclic: HashSet[Task]
    stack = toSeq(newDepends - task.depends)

  while stack.len > 0:
    let cur = stack.pop()
    if cur notin acyclic:
      acyclic.incl(cur)
      for v in cur.depends.items:
        if v == task:
          raise e
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
