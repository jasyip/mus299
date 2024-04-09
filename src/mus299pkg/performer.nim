import std/[sets, tables]
import std/sequtils
import std/strutils
import std/strformat


import core
import pool

import chronos
import chronos/asyncproc

const
  instrumentNames = toHashSet([
    "acoustic grand",
    "bright acoustic",
    "electric grand",
    "honky-tonk",
    "electric piano 1",
    "electric piano 2",
    "harpsichord",
    "clav",
    "celesta",
    "glockenspiel",
    "music box",
    "vibraphone",
    "marimba",
    "xylophone",
    "tubular bells",
    "dulcimer",
    "drawbar organ",
    "percussive organ",
    "rock organ",
    "church organ",
    "reed organ",
    "accordion",
    "harmonica",
    "concertina",
    "acoustic guitar (nylon)",
    "acoustic guitar (steel)",
    "electric guitar (jazz)",
    "electric guitar (clean)",
    "electric guitar (muted)",
    "overdriven guitar",
    "distorted guitar",
    "guitar harmonics",
    "acoustic bass",
    "electric bass (finger)",
    "electric bass (pick)",
    "fretless bass",
    "slap bass 1",
    "slap bass 2",
    "synth bass 1",
    "synth bass 2",
    "violin",
    "viola",
    "cello",
    "contrabass",
    "tremolo strings",
    "pizzicato strings",
    "orchestral harp",
    "timpani",
    "string ensemble 1",
    "string ensemble 2",
    "synthstrings 1",
    "synthstrings 2",
    "choir aahs",
    "voice oohs",
    "synth voice",
    "orchestra hit",
    "trumpet",
    "trombone",
    "tuba",
    "muted trumpet",
    "french horn",
    "brass section",
    "synthbrass 1",
    "synthbrass 2",
    "soprano sax",
    "alto sax",
    "tenor sax",
    "baritone sax",
    "oboe",
    "english horn",
    "bassoon",
    "clarinet",
    "piccolo",
    "flute",
    "recorder",
    "pan flute",
    "blown bottle",
    "shakuhachi",
    "whistle",
    "ocarina",
    "lead 1 (square)",
    "lead 2 (sawtooth)",
    "lead 3 (calliope)",
    "lead 4 (chiff)",
    "lead 5 (charang)",
    "lead 6 (voice)",
    "lead 7 (fifths)",
    "lead 8 (bass+lead)",
    "pad 1 (new age)",
    "pad 2 (warm)",
    "pad 3 (polysynth)",
    "pad 4 (choir)",
    "pad 5 (bowed)",
    "pad 6 (metallic)",
    "pad 7 (halo)",
    "pad 8 (sweep)",
    "fx 1 (rain)",
    "fx 2 (soundtrack)",
    "fx 3 (crystal)",
    "fx 4 (atmosphere)",
    "fx 5 (brightness)",
    "fx 6 (goblins)",
    "fx 7 (echoes)",
    "fx 8 (sci-fi)",
    "sitar",
    "banjo",
    "shamisen",
    "koto",
    "kalimba",
    "bagpipe",
    "fiddle",
    "shanai",
    "tinkle bell",
    "agogo",
    "steel drums",
    "woodblock",
    "taiko drum",
    "melodic tom",
    "synth drum",
    "reverse cymbal",
    "guitar fret noise",
    "breath noise",
    "seashore",
    "bird tweet",
    "telephone ring",
    "helicopter",
    "applause",
    "gunshot",
    "standard kit",
    "standard drums",
    "drums",
    "room kit",
    "room drums",
    "power kit",
    "power drums",
    "rock drums",
    "electronic kit",
    "electronic drums",
    "tr-808 kit",
    "tr-808 drums",
    "jazz kit",
    "jazz drums",
    "brush kit",
    "brush drums",
    "orchestra kit",
    "orchestra drums",
    "classical drums",
    "sfx kit",
    "sfx drums",
    "mt-32 kit",
    "mt-32 drums",
    "cm-64 kit",
    "cm-64 drums",
  ])
  staffPrefixes = toHashSet([
    "",
    "Drum",
    "Tab",
  ])


proc newInstrument*(name: string; staffPrefix: string; semitoneTranspose: range[-127..127]): Instrument =
  let
    lowerName = name.toLowerAscii()
    titleStaffPrefix = staffPrefix.toLowerAscii().capitalizeAscii()

  if lowerName notin instrumentNames:
    raise ValueError.newException("name must be actual MIDI instrument")
  if titleStaffPrefix notin staffPrefixes:
    raise ValueError.newException("unsupported staff prefix")

  Instrument(name:lowerName, staffPrefix: titleStaffPrefix, semitoneTranspose: semitoneTranspose)

proc perform*(performer: Performer; pool: TaskPool;
              player: string; playerParams: seq[string];
              afterPop: proc(x: Task): Future[void] {.gcsafe, raises: [].} = nil;
              categories: HashSet[Category] = performer.categories) {.async.} =
  assert performer.state != Performing
  let task = await pool.popTask(categories)

  if not afterPop.isNil():
    await afterPop(task)

  #[
  assert anyIt({
      categories: false,
      task.allowedCategories: false,
      categories * task.allowedCategories: true,
      }, (it[0].len > 0) == it[1])
  ]#

  performer.state = Performing
  performer.currentTasks.add(task)
  block:
    let playerProc = await startProcess(player, task.snippet.path.string,
                                        concat(playerParams,
                                               @[&"source-{performer.name}.midi"]
                                              ),
                                        options={UsePath}
                                       )
    defer: await playerProc.closeWait()
    var
      accumulatingOffset = nanoseconds(0)
      suspended = false

    for offset, childCategories in task.children.pairs:
      if accumulatingOffset < offset:
        if suspended:
          playerProc.resume.tryGet()
          suspended = false
        await sleepAsync(offset - accumulatingOffset)
        accumulatingOffset = offset
      if not suspended:
        playerProc.suspend.tryGet()
        suspended = true
      performer.state = Blocking
      await perform(performer, pool, player, playerParams, afterPop, childCategories)

    if suspended:
      playerProc.resume.tryGet()

    let code = await playerProc.waitForExit()
    if code != 0:
      raise OSError.newException(&"lilypond return code was {code}")

  performer.state = Ready
  for t in task.dependents:
    t.depends.excl(task)
    pool.addTask(t)

proc perform*(performer: Performer; pool: TaskPool;
              player: string; playerParams: seq[string];
              afterPop: proc(x: Task) {.gcsafe, raises: [].};
              categories: HashSet[Category] = performer.categories) {.async: (raw: true).} =
  proc asyncAfterPop(x: Task) {.async.} =
    afterPop(x)
  perform(performer, pool, player, playerParams, asyncAfterPop, categories)
