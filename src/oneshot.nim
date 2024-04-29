import mus299pkg/[core, task, pool, performer]
import std/appdirs
import std/re
import std/[paths, tempfiles]
import std/sets
import std/random
import std/macros
import std/strutils except strip
from std/strbasics import strip
import std/enumerate
import std/sequtils
from std/unicode import title


import chronos
import results



const
  expressionRe = r"\s*(?:\\\w+\s*)*\{" 

  dataDir = getDataDir() / "mus299".Path

  player = "aplaymidi"
  playerParams = @["-p", "128", "-d", "0"]


func normalizeIdent(x: string): string =
 let normalized = x.title.multiReplace((" ", ""), ("(", ""), (")", ""))
 toLowerAscii(normalized[0]) & normalized[1..^1]

macro createPerf(pool: TaskPool;
                 categories: HashSet[Category];
                 staffPrefix, key, clef: string;
                 maxVolume: float,
                 args: varargs[untyped];
                ): untyped =
  result = nnkStmtList.newTree()
  for i in args:
    let
      s = i.strVal.newLit
      x = i.strVal.normalizeIdent.ident
      p = ident(strVal(x) & "P")
      quoted = quote do:
        let
          `x` = newInstrument(`s`, `staffPrefix`)
          `p` = Performer(categories: `categories`, name: `i`, instrument: `x`, key: `key`, clef: `clef`, maxVolume: `maxVolume`)
        `pool`.instruments.incl(`x`)
        `pool`.performers.incl(`p`)
    for statement in quoted:
      result.add(statement)


proc newSnippet(pool: TaskPool;
                snippet: string;
                futures: var seq[(TaskSnippet, Future[Result[void, string]])];
                name, key, staffPrefix: string;
                channel: uint = 0;
               ): TaskSnippet =
  result = TaskSnippet(path: createTempDir("mus299-" & name & "-", "").Path,
                       snippet: snippet,
                       name: name,
                       key: key,
                       staffPrefix: staffPrefix,
                       channel: channel,
                      )
  strip(result.snippet)
  pool.tasksnippets.incl(result)
  futures.add((result, result.resyncTaskSnippet(pool)))

macro taskGraph(pool: TaskPool; categories: HashSet[Category]; snip: untyped; varSuffix: static[uint], args: varargs[untyped]): untyped =
  # each args is a tuple
  result = nnkStmtList.newTree()
  for i, level in enumerate(args):
    let
      levelSet = nnkBracket.newTree()
      levelSetName = ident(strVal(snip) & $varSuffix & "Level" & $i)
      prevLevelSet = ident(strVal(snip) & $varSuffix & "Level" & $max(0, i - 1))

    for j, suffix in enumerate(level):
      let
        snippetName = ident(strVal(snip) & (if suffix.kind == nnkIntLit: $suffix.intVal else: strVal(suffix)))
        taskName = ident(strVal(snip) & $varSuffix & $i & "Task" & $j)
      result.add:
        if i > 0:
          quote do:
            let `taskName` = Task(snippet: `snippetName`, allowedCategories: `categories`, depends: `prevLevelSet`)
        else:
          quote do:
            let `taskName` = Task(snippet: `snippetName`, allowedCategories: `categories`)
      let setup = quote do:
        `pool`.tasks.incl(`taskName`)
        block:
          for i in `taskName`.depends:
            i.dependents.incl(`taskName`)
      for s in setup:
        result.add(s)
      if i == 0:
        result.add quote do:
          `pool`.initialPool.incl(`taskName`)
      if i < args.len - 1:
        levelSet.add(taskName)
    if i < args.len - 1:
      result.add quote do:
        let `levelSetName` = toHashSet(`levelSet`)

proc main {.async.} =

  randomize()
  let
    chords = toHashSet(["chords".Category])
    bowed = toHashSet(["bowed".Category])
    organ = toHashSet(["organ".Category])
    eguit = toHashSet(["eguit".Category])
    brass = toHashSet(["brass".Category])
    bass = toHashSet(["bass".Category])
    drums = toHashSet(["drums".Category])

  let pool = TaskPool(
                      varName: "task",
                      isExpression: re(r"^" & expressionRe, {reIgnoreCase, reMultiLine, reStudy}),
                      isAssignment: re(r"^([a-z]+)\s*=" & expressionRe, {reMultiLine, reStudy}),
                      sourceTemplate: readFile(string(dataDir / "template.ly".Path)),
                      staffTemplate: readFile(string(dataDir / "staff.ly".Path)),
                      nameRe: re("[a-z0-9]+(_[a-z0-9]+)*[a-z0-9]*", flags = {reIgnoreCase, reStudy}),
                      tempo: "4 = 132",
                      timeSig: "4/4",
                     )

  createPerf(pool, chords, "", r"f, \minor", "", 0.5,
             "acoustic grand", "bright acoustic", "electric grand",
            )
  createPerf(pool, bowed, "", r"f' \minor", "", 1.0,
             "violin", "tremolo strings", "string ensemble 1", "string ensemble 2",
            )
  createPerf(pool, organ, "", "", "", 1.0,
             "alto sax", "drawbar organ", "rock organ",
            )
  createPerf(pool, eguit, "", "", "", 0.6,
             "electric guitar (clean)", "electric guitar (jazz)", "overdriven guitar",
            )
  createPerf(pool, brass, "", r"f, \minor", "", 1.0,
             "trumpet", "trombone", "muted trumpet", "brass section",
            )
  createPerf(pool, bass, "", "", "bass", 0.7,
             "fretless bass", "electric bass (finger)", "slap bass 1",
            )
  createPerf(pool, drums, "Drum", "", "", 1.0,
             "standard kit", "electronic kit", "jazz kit",
            )

  var futures: seq[(TaskSnippet, Future[Result[void, string]])]

  let
    chords11 = pool.newSnippet("""
      \chordmode {
        bf8.:maj q16 r4. g'8:m6.2^1/bf~ 16 16 r8 |
      }
      """, futures, "chords11", "f", "", 0)
    chords12 = pool.newSnippet("""
      \chordmode {
        af8.:maj q16 r4. f'8:m6.2^1/af~ 16 16 r8 |
      }
      """, futures, "chords12", "f", "", 0)
    chords13 = pool.newSnippet("""
      \chordmode {
        bf8.:maj q16 r4. a'8:m7+.2-^7/bf r af:m9^1~ |
        8 16 r4.. q8~ 16 af':m7/cf r8 |
      }
      """, futures, "chords13", "f", "", 0)
    chords14 = pool.newSnippet("""
      \chordmode {
        af4:m9^1 r8 bf:maj~ q4 r8 gf:m7^1~ |
        q2 af4\staccato q\staccato |
      }
      """, futures, "chords14", "f", "", 0)
    chords15 = pool.newSnippet("""
      \chordmode {
        g'2.:m/bf r8 bf:m7^5~ |
        q4 r8 g':dim/df~ 4 r8 c':m7^5~ |
        2. r8 af:m9^1.7~ |
        4 r8 q~ 4. r8 |
      }
      """, futures, "chords15", "f", "", 0)
    chords16 = pool.newSnippet("""
      \chordmode {
        df'2. r8 af~ |
        4 r8 bf~ 4 r8 c':m~ |
        2. r8 af~ |
        4 r8 f:m6.9^1~ q4. r8 |
      }
      """, futures, "chords16", "f", "", 0)
    chords21 = pool.newSnippet("""
      \fixed c' {
        g8. 16 r4. c'8~ 16 16 r8 |
      }
      """, futures, "chords21", "f", "", 1)
    chords22 = pool.newSnippet("""
      \fixed c' {
        f8. 16 r4. bf8~ 16 16 r8 |
      }
      """, futures, "chords22", "f", "", 1)
    chords23 = pool.newSnippet("""
      \fixed c' {
        g8. 16 r4. c'8 r af~ |
        8 16 r r8. af16 r af8 df' df'16 b8 |
      }
      """, futures, "chords23", "f", "", 1)
    chords24 = pool.newSnippet("""
      \fixed c' {
        df'4 8 c'~ 4 8 b~ |
        2 bf4-. 4-. |
      }
      """, futures, "chords24", "f", "", 1)
    chords25 = pool.newSnippet("""
      \fixed c' {
        ef'2. r8 bf~ |
        4 r8 ef'8~ 4 r8 af~ |
        2. r8 af~ |
        4 r8 df'~ 4. r8 |
      }
      """, futures, "chords25", "f", "", 1)
    chords26 = pool.newSnippet("""
      \fixed c' {
        gf2. r8 f~ |
        4 r8 g~ 4 r8 af~ |
        2. r8 bf~ |
        4 r8 bf~ 4. r8 |
      }
      """, futures, "chords26", "f", "", 1)

    bowed1 = pool.newSnippet("""
      r4. <bf bf,>8-. <c' c>-. <ef' ef>-. r4 |
      r4 <bf bf,>8-.  r <f' f>-. <c' c>-. r <bf bf,>~ |
      4
      """, futures, "bowed1", "f", "", 2)
    bowed2 = pool.newSnippet("""
      \partial 2.
      r8 <bf bf,>8-. <c' c>-. <ef' ef>-. r4 |
      r8 <gf' gf>-. r <f' f> r <ef' ef>4. |
      <g' g>8-. r r <bf bf,>8-. <c' c>-. <ef' ef>-. r4 |
      """, futures, "bowed2", "f", "", 2)
    bowed3 = pool.newSnippet("""
      r4 <bf bf,>8-.  r <f' f>-. <d' d>4. |
      <ef' ef>4. <d' d>8~ 4. <e' e>8~ | 
      4. r8 <g' g>4-. q-. |
      """, futures, "bowed3", "f", "", 2)

    organ10 = pool.newSnippet(r"\repeat unfold 8 r1",  futures, "organ10", "f", "", 3)
    organ11 = pool.newSnippet("""
      \fixed c'' {
        bf8 f16 g~ 4. r8 f g |
        f8 c16 ef~ 4. r8 8 f |
        g8. 16 r8 bf~ 8 g r ef'~ |
        8 16 r df'8 ef' \acciaccatura af8 a8. af16~ 8 gf |
      }
      """, futures, "organ11", "f", "", 3)
    organ12 = pool.newSnippet("""
      \fixed c'' {
        bf8 f16 g~ 4. r8 f g |
        f8 c16 ef~ 4. r8 8 f |
        g4 r8 bf~ 4 r8 af~ |
        2 b4-. 4-. |
      }
      """, futures, "organ12", "f", "", 3)
    organ20 = pool.newSnippet(r"\repeat unfold 16 r1",  futures, "organ20", "f", "", 4)
    organ21 = pool.newSnippet("""
      \fixed c'' {
        bf8 f16 g~ 4. r8 f g |
        f8 c16 ef~ 4. r8 8 f |
        g8. 16 r8 bf~ 8 g r ef'~ |
        8 16 r df'8 ef' \acciaccatura af8 a8. af16~ 8 gf |
      }
      """, futures, "organ21", "f", "", 4
    )
    organ22 = pool.newSnippet("""
      \fixed c'' {
        bf8 f16 g~ 4. r8 f g |
        f8 c16 ef~ 4. r8 8 f |
        g4 r8 bf~ 4 r8 af~ |
        2 b4-. 4-. |
      }
      """, futures, "organ22", "f", "", 4
    )

    brass10 = pool.newSnippet(r"\repeat unfold 24 r1", futures, "brass10", "f", "", 5)
    brass11 = pool.newSnippet("""
      \fixed c'' {
        bf2 r8 bf r c' |
        r8 bf r f4. g8 f~ |
        8 c ef2. |
      }
      """, futures, "brass11", "f", "", 5)
    brass12 = pool.newSnippet("""
      \fixed c'' {
        r4. ef cf4 |
        bf,2 r8 af, bf, c~ |
        4 r8 d~ 4 r8 ef~ |
        4 r8 f~ 8 ef f g~ |
        4 r8 f~ 8 ef4 f8 |
      }
      """, futures, "brass12", "f", "", 5)
    brass13 = pool.newSnippet("""
      \fixed c'' {
        bf2 r4 bf8 c' |
        r8 bf r g~ 4 bf8-. f~ |
        8 ef2..~ |
        4 
      }
      """, futures, "brass13", "f", "", 5)
    brass14 = pool.newSnippet("""
      \fixed c''' {
        \partial 2.
        r4 ef c8 r |
        bf,2 r8 bf, f ef~ |
        4. r8 ef r f r |
        af4 r8 g r ef, r gf~ |
        8 f r ef r cs4 r8 |
      }
      """, futures, "brass14", "f", "", 5)
    brass20 = pool.newSnippet(r"\repeat unfold 32 r1", futures, "brass20", "f", "", 6)
    brass23 = pool.newSnippet("""
      \fixed c'' {
        bf2 r4 bf8 c' |
        r8 bf r g~ 4 bf8-. f~ |
        8 ef2..~ |
        4 
      }
      """, futures, "brass23", "f", "", 5)
    brass24 = pool.newSnippet("""
      \fixed c'' {
        \partial 2.
        r4 ef c8 r |
        bf,2 r8 bf, f ef~ |
        4. r8 ef r f r |
        af4 r8 g r ef, r gf~ |
        8 f r ef r cs4 r8 |
      }
      """, futures, "brass24", "f", "", 5)

    bass1 = pool.newSnippet("""
      g,8 d16 f r g r g r f d8 d16 d g8 |
      """, futures, "bass1", "f", "", 7)
    bass2 = pool.newSnippet("""
      f,8 c16 ef r f r f r ef c r f, f bf,8 |
      """, futures, "bass2", "f", "", 7)
    bass3 = pool.newSnippet("""
      g,8 d16 f r g r g r f d8. c16 af,8~ |
      8 8 gf df16 c r b, df r b, af,8. |
      """, futures, "bass3", "f", "", 7)
    bass4 = pool.newSnippet("""
      g,8 d16 f r g r g r f d8 d16 f8. |
      """, futures, "bass4", "f", "", 7)
    bass5 = pool.newSnippet("""
      g,8 c16 ef r e r f r ef c r bf, af,8. |
      """, futures, "bass5", "f", "", 7)
    bass6 = pool.newSnippet("""
      df8 af16 b8 df'16 c'8~ 16 bf af8 ef b,~ |
      8 8 16 b8 fs16 bf,8 g, bf,4 |
      """, futures, "bass6", "f", "", 7)
    bass7 = pool.newSnippet("""
      ef8 r ef r16 ef r8 ef r bf,~ |
      """, futures, "bass7", "f", "", 7)
    bass8 = pool.newSnippet("""
      8 8 f ef~ 8 8 g, af,~ |
      8 8 ef g r af r af~ |
      8 8 ef df~ 8 b,~ 16 r df8 |
      """, futures, "bass8", "f", "", 7)
    bass9 = pool.newSnippet("""
      gf,8 r gf, r16 gf, r8 gf, df f,~ |
      """, futures, "bass9", "f", "", 7)
    bass10 = pool.newSnippet("""
      8 8 r8 g,~ 8 8 r af,~ |
      8 8 af af,~ 8 ef f bf,~ |
      8 8 c ef~ 8 af bf16 f8.
      """, futures, "bass10", "f", "", 7)

    drums11 = pool.newSnippet("""
      <cymc hh>8 hh <sn hh> hh hh hh <sn hh> hh |
      """, futures, "drums11", "", "Drum")
    drums12 = pool.newSnippet("""
      hh8 hh <sn hh> hh hh hh <sn hh> hh |
      """, futures, "drums12", "", "Drum")
    drums13 = pool.newSnippet("""
      hh8 hh <sn hh> hh hh hh <sn hh> cymc |
      """, futures, "drums13", "", "Drum")
    drums14 = pool.newSnippet("""
      s8 hh <sn hh> hh hh hh <sn hh> hh |
      """, futures, "drums14", "", "Drum")
    drums15 = pool.newSnippet("""
      cymc8 hh <sn hh> <hh cymr> r hh <sn hh> <hh cymc>
      """, futures, "drums15", "", "Drum")
    drums21 = pool.newSnippet("""
      bd8 r s s r bd r bd |
      """, futures, "drums21", "", "Drum")
    drums22 = pool.newSnippet("""
      r8 bd s s r bd r bd |
      """, futures, "drums22", "", "Drum")

  pool.taskGraph(chords, chords, 1,
                 [11, 21], [12, 22], [13, 23], [11, 21], [12, 22], [14, 24],
                 [11, 21], [12, 22], [13, 23], [11, 21], [12, 22], [14, 24],
                 [11, 21], [12, 22], [13, 23], [11, 21], [12, 22], [14, 24],
                 [15, 25], [16, 26],
                 [15, 25], [16, 26],
                )
  pool.taskGraph(bowed, bowed, 1, [1], [2], [3])
  pool.taskGraph(organ, organ, 1, [10], [11], [12], [11], [12])
  pool.taskGraph(chords, organ, 2, [10], [11], [12], [11], [12])
  pool.taskGraph(eguit, organ, 3, [20], [21], [22])
  pool.taskGraph(brass, brass, 1, [10], [11], [12], [13], [14])
  pool.taskGraph(organ, brass, 2, [20], [23], [24])
  pool.taskGraph(bass, bass, 1,
                 [1], [2], [3], [4], [5], [6],
                 [1], [2], [3], [4], [5], [6],
                 [1], [2], [3], [4], [5], [6],
                 [7], [8], [9], [10],
                 [7], [8], [9], [10],
                )
  pool.taskGraph(drums, drums, 1,
                 [11, 21], [12, 21], [13, 21], [14, 22], [12, 21], [12, 21], [15, 21], [14, 22],
                 [11, 21], [12, 21], [13, 21], [14, 22], [12, 21], [12, 21], [15, 21], [14, 22],
                 [11, 21], [12, 21], [13, 21], [14, 22], [12, 21], [12, 21], [15, 21], [14, 22],
                 [11, 21], [12, 21], [13, 21], [14, 22], [12, 21], [12, 21], [15, 21], [14, 22],
                 [11, 21], [12, 21], [13, 21], [14, 22], [12, 21], [12, 21], [15, 21], [14, 22],
                )

  var
    reachable: HashSet[Task]
    cur = toSeq(pool.initialPool)
  echo "Initial pool:"
  for i in pool.initialPool:
    echo i.snippet.name
  while cur.len > 0:
    let x = cur.pop()
    if not reachable.containsOrIncl(x):
      for i in x.dependents:
        cur.add(i)
  echo "# reached: ", len(reachable), ", # total: ", len(pool.tasks)

  await futures.mapIt(it[1]).allFutures()

  for (snippet, fut) in futures:
    if fut.completed() and fut.read.isOk:
      continue
    echo snippet.name & " at " & snippet.path.string & " failed!"
    if fut.completed():
      fut.read.tryGet()
    raise fut.readError()



  echo "Done synchronizing!"

  while true:

    while true:
      stdout.write("Perform (Y/n)? ")
      case (try: readLine(stdin) except EOFError: "N"):
      of "Y": break
      of "n", "N":
        echo "\pBye!"
        return
      else: discard
    echo "Performing now!"

    discard await pool.startPerformance(player, playerParams).withTimeout(73750.milliseconds)

    await pool.endPerformance()



when isMainModule:
  waitFor main()
