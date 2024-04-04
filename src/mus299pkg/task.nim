import std/[paths, tempfiles]
import std/[strutils, unicode]
import std/sets
import std/re
import std/streams

import chronos
import chronos/asyncproc

import core



proc resyncTaskSnippet*(snippet: TaskSnippet;
                        pool: TaskPool;
                        isExpression, isAssignment: Regex;
                        staffJoinStr, varName,
                        sourceTemplate, staffTemplate: string;
                       ): Future[void] {.async.} =
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
      if i > 0:
        file.write(staffJoinStr)
      file.write(format($staffTemplate,
        "instrumentName", title(performer.name),
        "midiInstrument", performer.name,
        "staffPrefix", performer.staffPrefix,
      ))

  let p = await startProcess("lilypond", snippet.path.string, @["source.ly"])
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




template newTask*(snippet: TaskSnippet; args: varargs[typed]): Task =
  result = Task(snippet: snippet, args)
  for parent in result.depends:
    parent.dependents.incl(result)
