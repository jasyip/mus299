import std/appdirs
import std/re
import std/paths
import std/sets
import std/random
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


proc popJsonAsync*(b: ptr ABackend; s: ptr cstring): Future[JsonNode] {.async.} =
  await wait(b.b.signal)

  if s.isNil:
    return newJNull()

  defer:
    freeShared(cast[ptr char](s[]))
    s[] = nil
  let json = parseJson($s[])
  if json.kind == JObject:
    if "error" in json:
      raise ValueError.newException(json["error"].str)
    json.delete("error")
  json

proc respondMessage(b: ptr ABackend; msg: string): Future[bool] {.async.} =
  await b.lock.acquire()
  defer: b.lock.release()
  if not b.b.fromBData.isNil:
    freeShared(cast[ptr char](b.b.fromBData))
  b.b.fromBData = cast[cstring](createSharedU(byte, msg.len + 1))
  copyMem(b.b.fromBData, msg.cstring, msg.len + 1)
  await fire(b.b.signal)


proc readMessage(b: ptr ABackend;
                 pool: TaskPool;
                 performanceFut: ptr Future[void];
                ): Future[string] {.async.} =


  let
    json = await popJsonAsync(b, b.b.toBData.addr)
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
    changeDependencies(what, depends)

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
    result = $ %* toJson(cast[TaskSnippet](cast[pointer](json["address"].num)))
  of "getTaskSnippets":
    let xs = collect:
      for i in pool.tasksnippets:
        toJson(i)
    result = $ %* xs
  of "getTask":
    result = $ %* toJson(cast[Task](cast[pointer](json["address"].num)), pool)
  of "getTasks":
    let xs = collect:
      for i in pool.tasks:
        toJson(i, pool)
    result = $ %* xs
  of "getInstrument":
    result = $ %* toJson(cast[Instrument](cast[pointer](json["address"].num)))
  of "getInstruments":
    let xs = collect:
      for i in pool.instruments:
        toJson(i)
    result = $ %* xs
  of "getPerformer":
    result = $ %* toJson(cast[Performer](cast[pointer](json["address"].num)))
  of "getPerformers":
    let xs = collect:
      for i in pool.performers:
        toJson(i)
    result = $ %* xs
  of "start":
    # TODO: resync code here
    # and signal to frontend every svg path so that they can cache.
    # then after waiting for signal, start performance
    await fire(b.b.signal)
    await wait(b.b.signal)

    performanceFut[] = startPerformance(pool, player, playerParams)
  of "stop":
    await endPerformance(pool)
    try:
      performanceFut[].read()
    except CancelledError:
      discard
    performanceFut[] = nil
  else:
    raise ValueError.newException("unrecognized")

proc respondMessage(b: ptr ABackend;
                    pool: TaskPool;
                    performanceFut: ptr Future[void];
                   ): Future[bool] {.async.} =
  let msg = try: await readMessage(b, pool, performanceFut)
            except ValueError as e:
              let j = newJObject()
              j["error"] = % e.msg
              $j
  await respondMessage(b, msg)

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
    discard waitFor(respondMessage(ab.addr, pool, performanceFut.addr))







pointerList(TaskSnippet)
pointerList(Task)
pointerList(Instrument)
pointerList(Performer)

viewable App:
  b: ptr Backend
  performers {.private.}: ref HashSet[PerformerJson]
  svgcache {.private.}: Table[string, Pixbuf]
  curpaths {.private.}: seq[string]
  synchronizing {.private.}: bool
  performing {.private.}: bool
  tempo {.private.}: string
  timeSig {.private.}: string

  hooks performers:
    build:
      new(state.performers)


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
            for p in app.curpaths:
              Picture {.expand: false, hAlign: AlignStart, vAlign: AlignStart.}:
                pixbuf = app.svgcache[p]
                contentFit = ContentCover
                # sizeRequest = (-1, 150)


        ScrolledWindow:
          Box:
            orient = OrientY
            margin = padding
            spacing = padding

            # TODO: display of current tasks/performers/etc. here
            # TODO: ContextMenu

            TaskSnippetList()

            TaskList()

            InstrumentList()

            PerformerList()

            Separator() {.expand: false.}

            # configuration options
            Box:
              orient = OrientX

              Entry:
                placeholder = r"Tempo (denominator = bpm)"
                sensitive = not (app.synchronizing or app.performing)

                proc changed(text: string) = 
                  app.tempo = text

              Entry:
                placeholder = r"Time Signature (numerator/denominator)"
                sensitive = not (app.synchronizing or app.performing)

                proc changed(text: string) = 
                  app.timeSig = text

            Separator() {.expand: false.}

            # Start/stop button that resyncs before starting if necessary
            Button:
              text = case app.performing.uint shl 1 or app.synchronizing.uint:
                     of 0b00: "Perform!"
                     of 0b01: "Synchronizing..."
                     of 0b10: "Cancel"
                     of 0b11: "Cancelling..."
                     else: raiseAssert ""
              sensitive = not app.synchronizing
              style = [ButtonSuggested]

              proc clicked() =
                app.synchronizing = true
                defer: app.synchronizing = false

                if app.performing:
                  echo "stopping performance"
                  discard sendToB(app.b[], "stop")
                  discard waitSync(app.b[])
                else:
                  #[
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
                  ]#

                  discard sendToB(app.b[], "setTempo", %app.tempo)
                  discard waitSync(app.b[])
                  discard sendToB(app.b[], "setTimeSig", %app.timeSig)
                  discard waitSync(app.b[])
                  discard sendToB(app.b[], "start")
                  discard waitSync(app.b[])
                  let j = popJson(app.b[], app.b.fromBData)
                  app.svgcache.clear()
                  for path in j.elems:
                    app.svgcache[path.str] = loadPixbuf(path.str)
                  discard fireSync(app.b[])
                  discard waitSync(app.b[])

                  echo "playing now"



proc main =

  randomize()

  # TODO: GC_fullCollect then GC_disable right before playing, GC_enable after
  # GC_step whenevever the one and only task from pool is popped for 5 microsecs

  putEnv("GTK_THEME", "Default")

  let backend = createShared(Backend)
  backend.signal = ThreadSignalPtr.new.expect("free file descriptor for signal")
  var thread: Thread[ptr Backend]

  createThread(thread, backendThread, backend)

  brew(gui(App(b=backend)))

when isMainModule:
  main()
