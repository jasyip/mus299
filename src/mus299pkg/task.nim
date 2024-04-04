import std/[paths, tempfiles]
import std/[strutils, unicode]
import std/sets
import std/re
import std/streams
import std/os

import chronos
import chronos/asyncproc

import core




proc readFileAsCString(x: Path): cstring =
  let size = getFileSize(x.string).uint64
  result = cast[cstring](createU(char, size + 1))
  let f = open(x.string)
  defer: f.close()
  if readBuffer(f, result, size).uint < size:
    raise OSError.newException("buffer reading failed")
  result[size] = '\0'


let
  fileParent = instantiationInfo().filename.Path.parentDir()
  sourceTemplate = readFileAsCString(fileParent / "template.ly".Path)
  staffTemplate = readFileAsCString(fileParent / "staff.ly".Path)

const
  staffJoinStr = "\p"
  varName = "task"
  expressionRe = r"\s*(?:\\\w+\s*)*\{" 
  isExpression = r"^" & expressionRe
  isAssignment = r"^([a-z]+)\s*=" & expressionRe


proc newTaskSnippet*(snippet: string;
                     pool: TaskPool
                    ): Future[TaskSnippet] {.async.} =
  let workdir = createTempDir("mus299", "").Path

  block:
    let file = openFileStream(string(workdir / "source.ly".Path), fmWrite)
    defer: file.close()
    file.write(sourceTemplate)

    file.write:
      # assume that snippet is already whitespace-stripped
      if "\p" in snippet:
        snippet
      else:
        var matches: array[1, string]
        if contains(snippet, re(isAssignment, {reIgnoreCase, reMultiLine}), matches):
          if matches[0] != varName:
            varName & snippet[matches[0].len .. ^1]
          else:
            raise ValueError.newException("Unparseable")
        else:
          varName & " = " & (if contains(snippet, re(isExpression, {reMultiLine})): snippet
                             else: "{" & snippet & "}")


    for i, performer in pool.performers.pairs:
      if i > 0:
        file.write(staffJoinStr)
      file.write(format($staffTemplate,
        "instrumentName", title(performer.name),
        "midiInstrument", performer.name,
        "staffPrefix", performer.staffPrefix,
      ))

  let p = await startProcess("lilypond", workdir.string, @["source.ly"])
  defer: await p.closeWait()
  if (await p.waitForExit(10 * Second)) != 0:
    raise OSError.newException("lilypond invocation failed")

  new(result)
  result[] = workdir.TaskSnippetObj



template newTask*(snippet: TaskSnippet; args: varargs[typed]): Task =
  result = Task(snippet: snippet, args)
  for parent in result.depends:
    parent.dependents.incl(result)
