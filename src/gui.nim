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
import std/strutils
import std/hashes

import results
import chronos
import owlkettle/owlkettle



import mus299pkg/[core, pool as taskpool, task]
import mus299pkg/gui/[pointer, tasksnippet, task, instrument, performer]





const
  expressionRe = r"\s*(?:\\\w+\s*)*\{" 

  dataDir = getDataDir() / "mus299".Path

  player = "aplaymidi"
  playerParams = @["-p128", "-d0"]

pointerList(TaskSnippet)
pointerList(Task)
pointerList(Instrument)
pointerList(Performer)

viewable App:
  pool: TaskPool
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
                      futures = mapIt(snippets, it.resyncTaskSnippet(app.pool, 4.seconds))

                    futures.allFutures.waitFor()
                    for i, future in enumerate(futures):
                      future.read.isOkOr:
                        try:
                          discard app.open: gui:
                            MessageDialog:
                              message = &"Error synchronizing task snippet \"{snippets[i].name}\":\p" & error

                              DialogButton {.addButton.}:
                                text = "Ok"
                                res = DialogAccept
                        except Exception:
                          discard
                        continue
                      for (performer, snippetcache) in app.svgcache.mpairs:
                        if (performer.instrument.staffPrefix == "Drum") != (snippets[i].staffPrefix == "Drum"):
                          snippetcache.del(snippets[i])
                          continue
                        snippetcache[snippets[i]] = loadPixbuf(string(snippets[i].path / Path("source-" & performer.name.hash.toHex() & ".cropped.svg")), width = -1, height = 150, preserveAspectRatio = true)
                      app.pool.resync.excl(snippets[i])
                    app.pool.resyncAll = false

                    if app.pool.resync.len > 0:
                      return

                  proc afterPop(_: Task) =
                    try:
                      discard app.redraw()
                    except Exception:
                      discard
                  asyncSpawn app.pool.startPerformance(player, playerParams, nil, afterPop)



proc main {.async.} =


  # TODO: GC_fullCollect then GC_disable right before playing, GC_enable after
  # GC_step whenevever the one and only task from pool is popped for 5 microsecs
  let pool = TaskPool(
                      varName: "task",
                      isExpression: re(r"^" & expressionRe, {reIgnoreCase, reMultiLine, reStudy}),
                      isAssignment: re(r"^([a-z]+)\s*=" & expressionRe, {reMultiLine, reStudy}),
                      sourceTemplate: readFile(string(dataDir / "template.ly".Path)),
                      staffTemplate: readFile(string(dataDir / "staff.ly".Path)),
                      nameRe: re("[a-z0-9]+(_[a-z0-9]+)*[a-z0-9]*", flags = {reIgnoreCase, reStudy}),
                     )

  putEnv("GTK_THEME", "Default")

  try:
    await brew(gui(App(pool=pool)))
  except Exception:
    discard

when isMainModule:
  randomize()

  waitFor main()
