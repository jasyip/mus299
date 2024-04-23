import std/appdirs
import std/re
import std/paths
import std/sets
import std/random

import chronos
import owlkettle



import mus299pkg/[core, pool, task]
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
                if not app.pool.resyncAll and app.pool.resync.len == 0:
                  discard app.redraw()

            TaskList:
              pool = app.pool

            InstrumentList:
              pool = app.pool
              proc delete(x: Instrument) =
                for p in app.pool.performers.items:
                  if p.instrument == x:
                    app.pool.performers.excl(p)

            PerformerList:
              pool = app.pool

            Separator() {.expand: false.}

            # configuration options
            Box:
              orient = OrientX

              Entry:
                placeholder = r"Tempo (in LilyPond's \tempo format)"
                sensitive = not (app.pool.synchronizing or app.pool.performing)

                proc changed(text: string) = 
                  app.pool.resyncAll = true
                  app.pool.tempo = text

              Entry:
                placeholder = r"Time Signature (in LilyPond's \time format)"
                sensitive = not (app.pool.synchronizing or app.pool.performing)

                proc changed(text: string) = 
                  app.pool.resyncAll = true
                  app.pool.timeSig = text

            Separator() {.expand: false.}

            # Start/stop button that resyncs before starting if necessary
            Button:
              text = case uint(app.pool.performing) shl 1 or uint(app.pool.synchronizing):
                     of 0b00: (if app.pool.resyncAll or
                                  app.pool.resync.len > 0: "Synchronize then Perform!"
                               else: "Perform!"
                              )
                     of 0b01: "Synchronizing..."
                     of 0b10:  "Cancel"
                     of 0b11:  "Cancelling..."
                     else: raiseAssert ""
              # sensitive = not app.pool.synchronizing
              style = [ButtonSuggested]

              proc clicked() =
                discard



when isMainModule:

  randomize()

  # TODO: GC_fullCollect then GC_disable right before playing, GC_enable after
  # GC_step whenevever the one and only task from pool is popped for 5 microsecs

  brew(gui(App(pool=TaskPool(
                             varName: "task",
                             isExpression: re(r"^" & expressionRe, {reIgnoreCase, reMultiLine, reStudy}),
                             isAssignment: re(r"^([a-z]+)\s*=" & expressionRe, {reMultiLine, reStudy}),
                             sourceTemplate: readFile(string(dataDir / "template.ly".Path)),
                             staffTemplate: readFile(string(dataDir / "staff.ly".Path)),
                             nameRe: re("[a-z0-9]+(_[a-z0-9]+)*[a-z0-9]*", flags = {reIgnoreCase, reStudy}),
                            )
              )
          )
      )
