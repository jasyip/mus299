import std/appdirs
import std/re
import std/paths
import std/sets
import std/random

import chronos
import owlkettle



import mus299pkg/[core, performer, pool, task]
import mus299pkg/gui/pointer




const
  expressionRe = r"\s*(?:\\\w+\s*)*\{" 

  dataDir = getDataDir() / "mus299".Path

  player = "aplaymidi"
  playerParams = @["-p", "128", "-d", "0"]

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
            Entry:
              placeholder = r"Tempo (in LilyPond's \tempo format)"

              proc changed(text: string) = 
                app.pool.resync = true
                app.pool.tempo = text

            Entry:
              placeholder = r"Time Signature (in LilyPond's \time format)"

              proc changed(text: string) = 
                app.pool.resync = true
                app.pool.timeSig = text

            Separator() {.expand: false.}

            # buttons that add/edit/delete tasks/performers/etc.

            Box:
              orient = OrientX
              margin = padding
              spacing = padding

              Button:
                text = "Add Task Snippet"
                proc clicked() =
                  discard

              Button:
                text = "Add Task"
                proc clicked() =
                  discard

              Button:
                text = "Add Instrument"
                proc clicked() =
                  discard

              Button:
                text = "Add Performer"
                proc clicked() =
                  discard

            Separator() {.expand: false.}

            # Start/stop button that resyncs before starting if necessary
            Button:
              proc clicked() =
                discard



when isMainModule:

  randomize()

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
