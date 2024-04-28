import std/appdirs
import std/re
import std/paths
import std/sets
import std/sequtils
import std/random
import std/enumerate
import std/strformat
import std/envvars
import std/tables
import std/json
import std/sugar

import results
import chronos
import owlkettle
import chronos/threadsync



import mus299pkg/[core, pool as taskpool, task]
import mus299pkg/gui/[pointer, tasksnippet, task, instrument, performer, communication]





const
  expressionRe = r"\s*(?:\\\w+\s*)*\{" 

  dataDir = getDataDir() / "mus299".Path

  player = "aplaymidi"
  playerParams = @["-p128", "-d0"]



type
  ABackend = object
    b: ptr Backend
    lock: AsyncLock

proc sendFromB(b: ABackend; s: string) {.async.} =
  await b.lock.acquire()
  defer: b.lock.release()
  if not b.b.fromBData.isNil:
    freeShared(cast[ptr char](b.b.fromBData))
  b.b.fromBData = cast[cstring](createSharedU(char, s.len + 1))
  copyMem(b.b.fromBData, s.cstring, s.len + 1)
  await fire(b.b.fromB)



proc readMessage(b: var ABackend;
                 pool: TaskPool;
                 performanceFut: var Future[void];
                ): Future[string] {.async.} =


  await wait(b.b[].toB)

  let
    json = parseJson($b.b[].toBData)
    m = json["method"].str

  json.delete("method")
  case m:
  of "newTaskSnippet":
    json["address"] = % 0
    json["path"] = % ""
    let
      j = to(json, TaskSnippetJson)
      x = TaskSnippet(snippet: j.snippet,
                      name: j.name,
                      key: j.key,
                      staffPrefix: j.staffPrefix,
                     )
    pool.tasksnippets.incl(x)
    if not pool.resyncAll:
      pool.resync.incl(x)
  of "newTask":
    json["address"] = % 0
    let
      j = to(json, TaskJson)
      depends = collect:
        for dep in j.depends:
          {cast[Task](cast[pointer](dep))}
      categories = collect:
        for cat in j.categories:
          {cat.Category}
  
    let x = Task(snippet: cast[TaskSnippet](cast[pointer](j.snippet)),
                 depends: depends,
                 allowedCategories: categories,
                )
    pool.tasks.incl(x)
    if j.inPool:
      pool.initialPool.incl(x)
  of "newInstrument":
    json["address"] = % 0
    let j = to(json, InstrumentJson)
    pool.instruments.incl(Instrument(name: j.name,
                                     staffPrefix: j.staffPrefix,
                                    ))
  of "newPerformer":
    json["address"] = % 0
    let
      j = to(json, PerformerJson)
      categories = collect:
        for cat in json["categories"].elems:
          {cat.str.Category}
    pool.performers.incl(Performer(name: j.name,
                                   categories: categories,
                                   instrument: cast[Instrument](cast[pointer](j.instrument)),
                                   minVolume: j.minVolume,
                                   maxVolume: j.maxVolume,
                                   key: j.key,
                                   clef: j.clef,
                                  ))
    pool.resyncAll = true
  of "updateTaskSnippet":
    json["path"] = % ""
    let j = to(json, TaskSnippetJson)
    let what = cast[TaskSnippet](cast[pointer](j.address))
    what.snippet = j.snippet
    what.name = j.name
    what.key = j.key
    what.staffPrefix = j.staffPrefix
    if not pool.resyncAll:
      pool.resync.incl(what)
  of "updateTask":
    let j = to(json, TaskJson)
    let what = cast[Task](cast[pointer](j.address))

    let
      depends = collect:
        for dep in j.depends:
          {cast[Task](cast[pointer](dep))}
    try:
      changeDependencies(what, depends)
    except ValueError as e:
      return e.msg

    what.snippet = cast[TaskSnippet](cast[pointer](j.snippet))
    what.allowedCategories = collect:
      for cat in j.categories:
        {cat.Category}
  of "updateInstrument":
    let j = to(json, InstrumentJson)
    let what = cast[Instrument](cast[pointer](j.address))
    what.name = j.name
    what.staffPrefix = j.staffPrefix
  of "updatePerformer":
    let j = to(json, PerformerJson)
    let what = cast[Performer](cast[pointer](j.address))
  
    what.instrument = cast[Instrument](cast[pointer](j.instrument))
    what.categories = collect:
      for cat in json["categories"].elems:
        {cat.str.Category}
    what.name = j.name
    what.minVolume = j.minVolume
    what.maxVolume = j.maxVolume
    what.key = j.key
    what.clef = j.clef
    pool.resyncAll = true
  of "delTaskSnippet":
    let toDel = cast[TaskSnippet](cast[pointer](json["address"].num))
    pool.tasksnippets.excl(toDel)
    pool.resync.excl(toDel)
  of "delTask":
    pool.tasks.excl(cast[Task](cast[pointer](json["address"].num)))
  of "delInstrument":
    pool.instruments.excl(cast[Instrument](cast[pointer](json["address"].num)))
  of "delPerformer":
    pool.performers.excl(cast[Performer](cast[pointer](json["address"].num)))
  of "setTempo":
    pool.tempo = json["tempo"].str
    pool.resyncAll = true
  of "setTimeSig":
    pool.timeSig = json["timeSig"].str
    pool.resyncAll = true
  of "getTaskSnippet":
    await b.sendFromB($ %* toJson(cast[TaskSnippet](cast[pointer](json["address"].num))))
  of "getTaskSnippets":
    let xs = collect:
      for i in pool.tasksnippets:
        toJson(i)
    await b.sendFromB($ %* xs)
  of "getTask":
    await b.sendFromB($ %* toJson(cast[Task](cast[pointer](json["address"].num)), pool))
  of "getTasks":
    let xs = collect:
      for i in pool.tasks:
        toJson(i, pool)
    await b.sendFromB($ %* xs)
  of "getInstrument":
    await b.sendFromB($ %* toJson(cast[Instrument](cast[pointer](json["address"].num))))
  of "getInstruments":
    let xs = collect:
      for i in pool.instruments:
        toJson(i)
    await b.sendFromB($ %* xs)
  of "getPerformer":
    await b.sendFromB($ %* toJson(cast[Performer](cast[pointer](json["address"].num))))
  of "getPerformers":
    let xs = collect:
      for i in pool.performers:
        toJson(i)
    await b.sendFromB($ %* xs)
  of "start":
    # TODO: resync code here
    performanceFut = startPerformance(pool, player, playerParams)
  of "stop":
    await endPerformance(pool)
    try:
      performanceFut.read()
    except CancelledError:
      discard
    performanceFut = nil
  else:
    return "unrecognized"

proc respondMessage(b: var ABackend;
                    pool: TaskPool;
                    performanceFut: var Future[void];
                   ) {.async.} =

  await b.sendFromB(try: await readMessage(b, pool, performanceFut)
                    except CatchableError as e: e.msg)

proc backendThread(b: ptr Backend) {.thread.} =

  let
    pool = TaskPool(
                    varName: "task",
                    isExpression: re(r"^" & expressionRe, {reIgnoreCase, reMultiLine, reStudy}),
                    isAssignment: re(r"^([a-z]+)\s*=" & expressionRe, {reMultiLine, reStudy}),
                    sourceTemplate: readFile(string(dataDir / "template.ly".Path)),
                    staffTemplate: readFile(string(dataDir / "staff.ly".Path)),
                    nameRe: re("[a-z0-9]+(_[a-z0-9]+)*[a-z0-9]*", flags = {reIgnoreCase, reStudy}),
                   )
  var
    ab = ABackend(b: b)
    performanceFut: Future[void]


  while true:
    waitFor(respondMessage(ab, pool, performanceFut))

















pointerList(TaskSnippet)
pointerList(Task)
pointerList(Instrument)
pointerList(Performer)

viewable App:
  b: Backend
  svgcache: Table[Performer, Table[TaskSnippet, Pixbuf]]


method view(app: AppState): Widget =
  const padding = 12
  gui:
    Window:
      title = "Async Perform"
      defaultSize = (1280, 720)

      Paned:

        # Display of each performance
        ScrolledWindow:
          Box:
            orient = OrientY
            margin = padding
            spacing = padding

            # children will be Pictures
            for performer in app.pool.performers:
              if not performer.performing.isNil:
                Picture {.expand: false, hAlign: AlignStart, vAlign: AlignStart.}:
                  pixbuf = app.svgcache[performer][performer.performing.snippet]
                  contentFit = ContentCover
                  # sizeRequest = (-1, 150)


        ScrolledWindow:
          Box:
            orient = OrientY
            margin = padding
            spacing = padding

            # TODO: display of current tasks/performers/etc. here
            # TODO: ContextMenu

            TaskSnippetList:
              pool = app.pool

              proc delete(x: TaskSnippet) =
                for t in app.pool.tasks.items:
                  if t.snippet == x:
                    app.pool.tasks.excl(t)
                app.pool.resync.excl(x)
                for snippetcache in app.svgcache.mvalues:
                  snippetcache.del(x)

            TaskList:
              pool = app.pool

            InstrumentList:
              pool = app.pool
              proc delete(x: Instrument) =
                for p in app.pool.performers.items:
                  if p.instrument == x:
                    app.pool.performers.excl(p)
                    app.svgcache.del(p)

            PerformerList:
              pool = app.pool
              proc delete(x: Performer) =
                app.svgcache.del(x)

            Separator() {.expand: false.}

            # configuration options
            Box:
              orient = OrientX

              Entry:
                placeholder = r"Tempo (denominator = bpm)"
                sensitive = not (app.pool.synchronizing or app.pool.performances.len > 0)

                proc changed(text: string) = 
                  app.pool.resyncAll = true
                  app.pool.tempo = text

              Entry:
                placeholder = r"Time Signature (numerator/denominator)"
                sensitive = not (app.pool.synchronizing or app.pool.performances.len > 0)

                proc changed(text: string) = 
                  app.pool.resyncAll = true
                  app.pool.timeSig = text

            Separator() {.expand: false.}

            # Start/stop button that resyncs before starting if necessary
            Button:
              text = case app.pool.performances.len.bool.uint shl 1 or app.pool.synchronizing.uint:
                     of 0b00: (if app.pool.resyncAll or
                                  app.pool.resync.len > 0: "Synchronize then Perform!"
                               else: "Perform!"
                              )
                     of 0b01: "Synchronizing..."
                     of 0b10:  "Cancel"
                     of 0b11:  "Cancelling..."
                     else: raiseAssert ""
              sensitive = not app.pool.synchronizing and
                              app.pool.tasksnippets.len > 0 and
                              app.pool.performers.len > 0 and
                              app.pool.initialPool.len > 0
              style = [ButtonSuggested]

              proc clicked() =
                defer:
                  app.pool.synchronizing = false
                if app.pool.performances.len > 0:
                  app.pool.synchronizing = true
                  echo "stopping performance"
                  waitFor app.pool.endPerformance()
                  app.pool.synchronizing = false
                else:
                  if app.pool.resyncAll or app.pool.resync.len > 0:
                    app.pool.synchronizing = true

                    for performer in app.pool.performers:
                      discard app.svgcache.hasKeyOrPut(performer, Table[TaskSnippet, Pixbuf].default)

                    if app.pool.resyncAll:
                      app.pool.resync.incl(app.pool.tasksnippets)
                    let
                      snippets = toSeq(app.pool.resync)
                      futures = mapIt(snippets, it.resyncTaskSnippet(app.pool))

                    futures.allFutures.waitFor()
                    for i, future in enumerate(futures):
                      future.read.isOkOr:
                        discard app.open: gui:
                          MessageDialog:
                            message = &"Error synchronizing task snippet \"{snippets[i].name}\":\p" & error

                            DialogButton {.addButton.}:
                              text = "Ok"
                              res = DialogAccept
                        continue
                      for (performer, snippetcache) in app.svgcache.mpairs:
                        if (performer.instrument.staffPrefix == "Drum") != (snippets[i].staffPrefix == "Drum"):
                          snippetcache.del(snippets[i])
                          continue
                        snippetcache[snippets[i]] = loadPixbuf(string(snippets[i].path / Path("source-" & performer.name & ".cropped.svg")), width = -1, height = 150, preserveAspectRatio = true)
                      app.pool.resync.excl(snippets[i])
                    app.pool.resyncAll = false

                    if app.pool.resync.len > 0:
                      return

                  proc afterPop() =
                    # try:
                    #   discard app.redraw()
                    # except:
                    #   discard
                    discard

                  # start performance
                  echo "starting performance"
                  waitFor app.pool.startPerformance(player, playerParams, afterPop)



proc main =

  randomize()

  # TODO: GC_fullCollect then GC_disable right before playing, GC_enable after
  # GC_step whenevever the one and only task from pool is popped for 5 microsecs

  putEnv("GTK_THEME", "Default")

  let backend = createShared(Backend)
  backend.toB = ThreadSignalPtr.new.expect("free file descriptor for signal")
  backend.fromB = ThreadSignalPtr.new.expect("free file descriptor for signal")
  var thread: Thread[ptr Backend]

  createThread(thread, backendThread, backend)

  brew(gui(App(pool=pool)))

when isMainModule:
  main()
