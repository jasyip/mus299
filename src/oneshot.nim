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
                 staffPrefix: string;
                 channel: static[uint];
                 key, clef: string;
                 maxVolume: float;
                 args: varargs[untyped];
                ): untyped =
  result = nnkStmtList.newTree()
  for i in args:
    let
      s = i.strVal.newLit
      x = (i.strVal & $channel).normalizeIdent.ident
      p = ident(strVal(x) & "P")
      quoted = quote do:
        let
          `x` = newInstrument(`s`, `staffPrefix`)
          `p` = Performer(categories: `categories`,
                          name: `i`,
                          instrument: `x`,
                          key: `key`,
                          clef: `clef`,
                          maxVolume: `maxVolume`,
                          channel: `channel`
                         )
        `pool`.instruments.incl(`x`)
        `pool`.performers.incl(`p`)
    for statement in quoted:
      result.add(statement)


proc newSnippet(pool: TaskPool;
                snippet: string;
                futures: var seq[(TaskSnippet, Future[Result[void, string]])];
                name, key, staffPrefix: string;
               ): TaskSnippet =
  result = TaskSnippet(path: createTempDir("mus299-" & name & "-", "").Path,
                       snippet: snippet,
                       name: name,
                       key: key,
                       staffPrefix: staffPrefix,
                      )
  strip(result.snippet)
  pool.tasksnippets.incl(result)
  futures.add((result, result.resyncTaskSnippet(pool)))

macro taskGraph(pool: TaskPool; snip: untyped; varSuffix: static[uint], args: varargs[untyped]): untyped =
  # each args is a tuple
  result = nnkStmtList.newTree()
  for i, level in enumerate(args):
    let
      levelSet = nnkBracket.newTree()
      levelSetName = ident(strVal(snip) & $varSuffix & "Level" & $i)
      prevLevelSet = ident(strVal(snip) & $varSuffix & "Level" & $max(0, i - 1))

    for j, suffix in enumerate(level):
      let
        snippetName = ident(strVal(snip) & "_" & (if suffix.kind == nnkIntLit: $suffix.intVal else: strVal(suffix)))
        taskName = ident(strVal(snip) & $varSuffix & $i & "Task" & $j)
      result.add:
        if i > 0:
          quote do:
            let `taskName` = Task(snippet: `snippetName`, allowedCategories: `snip`, depends: `prevLevelSet`)
        else:
          quote do:
            let `taskName` = Task(snippet: `snippetName`, allowedCategories: `snip`)
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

macro createCategories(parts: static[uint]): untyped =
  result = nnkStmtList.newTree()
  for i in 1..parts:
    let
      catName = ident("cat" & $i)
      asStr = strVal(catName).newLit()
    result.add quote do:
      let `catName` = toHashSet([Category(`asStr`)])

proc main {.async.} =

  createCategories(6)

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

  createPerf(pool, cat1, "Drum", 9, "", "", 1.0,
             "standard kit", "electronic kit", "jazz kit",
            )
  createPerf(pool, cat2, "", 0, r"f, \minor", "", 0.7,
             "acoustic grand", "bright acoustic", "electric grand",
            )
  createPerf(pool, cat3, "", 1, "", "bass", 0.7,
             "fretless bass", "electric bass (finger)", "slap bass 1",
            )
  createPerf(pool, cat4, "", 2, r"f' \minor", "", 1.0,
             "violin", "tremolo strings", "string ensemble 1", "string ensemble 2",
            )
  createPerf(pool, cat5, "", 2, r"f, \minor", "", 0.8,
             "acoustic grand", "bright acoustic", "electric grand",
            )
  createPerf(pool, cat5 + cat6, "", 3, "", "", 1.0,
             "alto sax", "drawbar organ", "rock organ",
            )
  createPerf(pool, cat5, "", 4, "", "", 0.6,
             "electric guitar (clean)", "electric guitar (jazz)", "overdriven guitar",
            )
  createPerf(pool, cat6, "", 2, r"f, \minor", "", 1.0,
             "trumpet", "trombone", "muted trumpet", "brass section",
            )

  var futures: seq[(TaskSnippet, Future[Result[void, string]])]

  let
    cat1_11 = pool.newSnippet("""
      <cymc hh>8 hh <sn hh> hh hh hh <sn hh> hh |
      """, futures, "cat1_11", "", "Drum")
    cat1_12 = pool.newSnippet("""
      hh8 hh <sn hh> hh hh hh <sn hh> hh |
      """, futures, "cat1_12", "", "Drum")
    cat1_13 = pool.newSnippet("""
      hh8 hh <sn hh> hh hh hh <sn hh> cymc |
      """, futures, "cat1_13", "", "Drum")
    cat1_14 = pool.newSnippet("""
      s8 hh <sn hh> hh hh hh <sn hh> hh |
      """, futures, "cat1_14", "", "Drum")
    cat1_15 = pool.newSnippet("""
      cymc8 hh <sn hh> <hh cymr> r hh <sn hh> <hh cymc>
      """, futures, "cat1_15", "", "Drum")
    cat1_21 = pool.newSnippet("""
      bd8 r s s r bd r bd |
      """, futures, "cat1_21", "", "Drum")
    cat1_22 = pool.newSnippet("""
      r8 bd s s r bd r bd |
      """, futures, "cat1_22", "", "Drum")

    cat2_11 = pool.newSnippet("""
      \chordmode {
        bf8.:maj q16 r4. g'8:m6.2^1/bf~ 16 16 r8 |
      }
      """, futures, "cat2_11", "f", "")
    cat2_12 = pool.newSnippet("""
      \chordmode {
        af8.:maj q16 r4. f'8:m6.2^1/af~ 16 16 r8 |
      }
      """, futures, "cat2_12", "f", "")
    cat2_13 = pool.newSnippet("""
      \chordmode {
        bf8.:maj q16 r4. a'8:m7+.2-^7/bf r af:m9^1~ |
        8 16 r4.. q8~ 16 af':m7/cf r8 |
      }
      """, futures, "cat2_13", "f", "")
    cat2_14 = pool.newSnippet("""
      \chordmode {
        af4:m9^1 r8 bf:maj~ q4 r8 gf:m7^1~ |
        q2 af4\staccato q\staccato |
      }
      """, futures, "cat2_14", "f", "")
    cat2_15 = pool.newSnippet("""
      \chordmode {
        g'2.:m/bf r8 bf:m7^5~ |
        q4 r8 g':dim/df~ 4 r8 c':m7^5~ |
        2. r8 af:m9^1.7~ |
        4 r8 q~ 4. r8 |
      }
      """, futures, "cat2_15", "f", "")
    cat2_16 = pool.newSnippet("""
      \chordmode {
        df'2. r8 af~ |
        4 r8 bf~ 4 r8 c':m~ |
        2. r8 af~ |
        4 r8 f:m6.9^1~ q4. r8 |
      }
      """, futures, "cat2_16", "f", "")
    cat2_21 = pool.newSnippet("""
      \fixed c' {
        g8. 16 r4. c'8~ 16 16 r8 |
      }
      """, futures, "cat2_21", "f", "")
    cat2_22 = pool.newSnippet("""
      \fixed c' {
        f8. 16 r4. bf8~ 16 16 r8 |
      }
      """, futures, "cat2_22", "f", "")
    cat2_23 = pool.newSnippet("""
      \fixed c' {
        g8. 16 r4. c'8 r af~ |
        8 16 r r8. af16 r af8 df' df'16 b8 |
      }
      """, futures, "cat2_23", "f", "")
    cat2_24 = pool.newSnippet("""
      \fixed c' {
        df'4 8 c'~ 4 8 b~ |
        2 bf4-. 4-. |
      }
      """, futures, "cat2_24", "f", "")
    cat2_25 = pool.newSnippet("""
      \fixed c' {
        ef'2. r8 bf~ |
        4 r8 ef'8~ 4 r8 af~ |
        2. r8 af~ |
        4 r8 df'~ 4. r8 |
      }
      """, futures, "cat2_25", "f", "")
    cat2_26 = pool.newSnippet("""
      \fixed c' {
        gf2. r8 f~ |
        4 r8 g~ 4 r8 af~ |
        2. r8 bf~ |
        4 r8 bf~ 4. r8 |
      }
      """, futures, "cat2_26", "f", "")

    cat3_1 = pool.newSnippet("""
      g,8 d16 f r g r g r f d8 d16 d g8 |
      """, futures, "cat3_1", "f", "")
    cat3_2 = pool.newSnippet("""
      f,8 c16 ef r f r f r ef c r f, f bf,8 |
      """, futures, "cat3_2", "f", "")
    cat3_3 = pool.newSnippet("""
      g,8 d16 f r g r g r f d8. c16 af,8~ |
      8 8 gf df16 c r b, df r b, af,8. |
      """, futures, "cat3_3", "f", "")
    cat3_4 = pool.newSnippet("""
      g,8 d16 f r g r g r f d8 d16 f8. |
      """, futures, "cat3_4", "f", "")
    cat3_5 = pool.newSnippet("""
      g,8 c16 ef r e r f r ef c r bf, af,8. |
      """, futures, "cat3_5", "f", "")
    cat3_6 = pool.newSnippet("""
      df8 af16 b8 df'16 c'8~ 16 bf af8 ef b,~ |
      8 8 16 b8 fs16 bf,8 g, bf,4 |
      """, futures, "cat3_6", "f", "")
    cat3_7 = pool.newSnippet("""
      ef8 r ef r16 ef r8 ef r bf,~ |
      """, futures, "cat3_7", "f", "")
    cat3_8 = pool.newSnippet("""
      8 8 f ef~ 8 8 g, af,~ |
      8 8 ef g r af r af~ |
      8 8 ef df~ 8 b,~ 16 r df8 |
      """, futures, "cat3_8", "f", "")
    cat3_9 = pool.newSnippet("""
      gf,8 r gf, r16 gf, r8 gf, df f,~ |
      """, futures, "cat3_9", "f", "")
    cat3_10 = pool.newSnippet("""
      8 8 r8 g,~ 8 8 r af,~ |
      8 8 af af,~ 8 ef f bf,~ |
      8 8 c ef~ 8 af bf16 f8.
      """, futures, "cat3_10", "f", "")

    cat4_1 = pool.newSnippet("""
      r4. <bf bf,>8-. <c' c>-. <ef' ef>-. r4 |
      r4 <bf bf,>8-.  r <f' f>-. <c' c>-. r <bf bf,>~ |
      4
      """, futures, "cat4_1", "f", "")
    cat4_2 = pool.newSnippet("""
      \partial 2.
      r8 <bf bf,>8-. <c' c>-. <ef' ef>-. r4 |
      r8 <gf' gf>-. r <f' f> r <ef' ef>4. |
      <g' g>8-. r r <bf bf,>8-. <c' c>-. <ef' ef>-. r4 |
      """, futures, "cat4_2", "f", "")
    cat4_3 = pool.newSnippet("""
      r4 <bf bf,>8-.  r <f' f>-. <d' d>4. |
      <ef' ef>4. <d' d>8~ 4. <e' e>8~ | 
      4. r8 <g' g>4-. q-. |
      """, futures, "cat4_3", "f", "")

    cat5_10 = pool.newSnippet(r"\repeat unfold 8 r1",  futures, "cat5_10", "f", "")
    cat5_11 = pool.newSnippet("""
      \fixed c'' {
        bf8 f16 g~ 4. r8 f g |
        f8 c16 ef~ 4. r8 8 f |
        g8. 16 r8 bf~ 8 g r ef'~ |
        8 16 r df'8 ef' \acciaccatura af8 a8. af16~ 8 gf |
      }
      """, futures, "cat5_11", "f", "")
    cat5_12 = pool.newSnippet("""
      \fixed c'' {
        bf8 f16 g~ 4. r8 f g |
        f8 c16 ef~ 4. r8 8 f |
        g4 r8 bf~ 4 r8 af~ |
        2 b4-. 4-. |
      }
      """, futures, "cat5_12", "f", "")
    cat5_20 = pool.newSnippet(r"\repeat unfold 16 r1",  futures, "cat5_20", "f", "")

    cat6_10 = pool.newSnippet(r"\repeat unfold 24 r1", futures, "cat6_10", "f", "")
    cat6_11 = pool.newSnippet("""
      \fixed c'' {
        bf2 r8 bf r c' |
        r8 bf r f4. g8 f~ |
        8 c ef2. |
      }
      """, futures, "cat6_11", "f", "")
    cat6_12 = pool.newSnippet("""
      \fixed c'' {
        r4. ef cf4 |
        bf,2 r8 af, bf, c~ |
        4 r8 d~ 4 r8 ef~ |
        4 r8 f~ 8 ef f g~ |
        4 r8 f~ 8 ef4 f8 |
      }
      """, futures, "cat6_12", "f", "")
    cat6_13 = pool.newSnippet("""
      \fixed c'' {
        bf2 r4 bf8 c' |
        r8 bf r g~ 4 bf8-. f~ |
        8 ef2..~ |
        4 
      }
      """, futures, "cat6_13", "f", "")
    cat6_14 = pool.newSnippet("""
      \fixed c''' {
        \partial 2.
        r4 ef c8 r |
        bf,2 r8 bf, f ef~ |
        4. r8 ef r f r |
        af4 r8 g r ef, r gf~ |
        8 f r ef r cs4 r8 |
      }
      """, futures, "cat6_14", "f", "")
    cat6_20 = pool.newSnippet(r"\repeat unfold 32 r1", futures, "cat6_20", "f", "")


  pool.taskGraph(cat1, 1,
                 [11, 21], [12, 21], [13, 21], [14, 22], [12, 21], [12, 21], [15, 21], [14, 22],
                 [11, 21], [12, 21], [13, 21], [14, 22], [12, 21], [12, 21], [15, 21], [14, 22],
                 [11, 21], [12, 21], [13, 21], [14, 22], [12, 21], [12, 21], [15, 21], [14, 22],
                 [11, 21], [12, 21], [13, 21], [14, 22], [12, 21], [12, 21], [15, 21], [14, 22],
                 [11, 21], [12, 21], [13, 21], [14, 22], [12, 21], [12, 21], [15, 21], [14, 22],
                )
  pool.taskGraph(cat2, 1,
                 [11, 21], [12, 22], [13, 23], [11, 21], [12, 22], [14, 24],
                 [11, 21], [12, 22], [13, 23], [11, 21], [12, 22], [14, 24],
                 [11, 21], [12, 22], [13, 23], [11, 21], [12, 22], [14, 24],
                 [15, 25], [16, 26],
                 [15, 25], [16, 26],
                )
  pool.taskGraph(cat3, 1,
                 [1], [2], [3], [4], [5], [6],
                 [1], [2], [3], [4], [5], [6],
                 [1], [2], [3], [4], [5], [6],
                 [7], [8], [9], [10],
                 [7], [8], [9], [10],
                )
  pool.taskGraph(cat4, 1, [1], [2], [3])
  pool.taskGraph(cat5, 1, [10], [11], [12], [11], [12])
  pool.taskGraph(cat5, 2, [10], [11], [12], [11], [12])
  pool.taskGraph(cat5, 3, [20], [11], [12])
  pool.taskGraph(cat6, 1, [10], [11], [12], [13], [14])
  pool.taskGraph(cat6, 2, [20], [13], [14])

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
  randomize()

  waitFor main()
