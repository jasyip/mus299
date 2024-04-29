import std/macros
import std/strutils

import ../../owlkettle/owlkettle

type EditDialogMode* = enum
  Add
  Update



macro autoIdent(args: varargs[untyped]): untyped = 
  result = newStmtList()
  for i in args:
    result.add(newLetStmt(i, newCall(ident("ident"), newStrLitNode(strVal(i)))))

macro pointerList*(t: typedesc): untyped = 

  let
    asStr = strVal(t)
    listName = ident(asStr & "List")
    listStateName = ident(asStr & "ListState")
    dialogName = ident(asStr & "Dialog")
    dialogStateName = ident(asStr & "DialogState")
    editorName = ident(asStr & "Editor")
    field = ident(asStr.toLowerAscii())
    widgetField = ident("val" & asStr[0].toUpperAscii() & asStr[1..^1].toLowerAscii())
    fieldSet = ident(asStr.toLowerAscii() & "s")

  autoIdent(text, title)

  quote do:

    viewable `dialogName`:
      pool: TaskPool
      `field`: `t`
      clone {.private.}: `t`


      hooks clone:
        build:
          let x = new(`t`)
          if not widget.`widgetField`.isNil:
            when `asStr` == "TaskSnippet":
              x.name = widget.`widgetField`.name
              x.snippet = widget.`widgetField`.snippet
              x.key = widget.`widgetField`.key
            else:
              x[] = widget.`widgetField`[]
          state.clone = x

    method view(dialog: `dialogStateName`): Widget =
      gui:
        Dialog:
          title = (if dialog.`field`.isNil: "Create" else: "Update") & " " & `asStr`

          DialogButton {.addButton.}:
            text = "Cancel"
            res = DialogCancel

          `editorName`:
            pool = dialog.pool
            `field` = dialog.clone
            original = dialog.`field`

    viewable `listName`:
      filter: string
      pool: TaskPool
      expanded {.private.}: bool
      proc delete(_: `t`)

    method view(state: `listStateName`): Widget =
      gui:
        Box:
          orient = OrientY
          Box {.expand: false.}:
            orient = OrientX
            Button {.expand: false.}:
              text = "Add " & `asStr`
              sensitive = `asStr` in ["Task", "Instrument"] or not
                          (state.pool.synchronizing or state.pool.performances.len > 0)
              proc clicked =
                let (res, dialogState) = state.app.open: gui:
                  `dialogName`:
                    `field` = nil
                    pool = state.pool

                if res.kind == DialogAccept:
                  # The "Update" button was clicked
                  let dState = `dialogStateName`(dialogState)
                  state.pool.`fieldSet`.excl(dState.`field`)
                  state.pool.`fieldSet`.incl(dState.clone)

            Button {.expand: false.}:
              text = "Delete All"
              sensitive = state.pool.`fieldSet`.len > 0
              proc clicked =
                if not state.delete.isNil:
                  for i in state.pool.`fieldSet`.items:
                    state.delete.callback(i)
                state.pool.`fieldSet`.clear()

          Box {.expand: false.}:
            orient = OrientX

            Label {.expand: false.}:
              text = "Search " & `asStr`
              xAlign = 0

            Entry:
              text = state.filter
              sensitive = state.pool.`fieldSet`.len > 0


          ScrolledWindow:
            ListBox:
              for i in state.pool.`fieldSet`.items:
                Box:
                  orient = OrientX

                  Label:
                    text = (when `asStr` == "Task": i.snippet.name & " | " & hexAddr(i)
                            else: i.name)
                    xAlign = 0

                  Button {.expand: false.}:
                    icon = "entity-edit"
                    sensitive = not (state.pool.performances.len > 0 or 
                                     (`asStr` != "Task" and
                                      state.pool.synchronizing))

                    proc clicked() =
                      discard state.app.open: gui:
                        `dialogName`:
                          `field` = i
                          pool = state.pool

                  Button {.expand: false.}:
                    icon = "user-trash-symbolic"
                    sensitive = not (state.pool.performances.len > 0 or 
                                     (`asStr` != "Task" and
                                      state.pool.synchronizing))

                    proc clicked() =
                      state.delete.callback(i)
                      state.pool.`fieldSet`.excl(i)
