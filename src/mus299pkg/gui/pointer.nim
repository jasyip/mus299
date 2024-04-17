import std/macros
import std/strutils

import owlkettle




macro autoIdent(args: varargs[untyped]): untyped = 
  result = newStmtList()
  for i in args:
    result.add(newLetStmt(i, newCall(ident("ident"), newStrLitNode(strVal(i)))))

macro pointerList*(t: typedesc): untyped = 

  let
    asStr = strVal(t)
    className = ident(asStr & "List")
    stateName = ident(asStr & "ListState")
    field = ident(asStr.toLowerAscii() & "s")

  autoIdent(text)

  quote do:

    viewable `className`:
      filter: string
      pool: TaskPool
      proc delete(_: `t`)

    method view(state: `stateName`): Widget =
      gui:
        Box:
          orient = OrientY
          Box {.expand: false.}:
            orient = OrientX
            Button {.expand: false.}:
              text = "Add " & `asStr`
              proc clicked =
                discard

            Button {.expand: false.}:
              text = "Delete All"
              proc clicked =
                for i in state.pool.`field`.items:
                  state.delete.callback(i)
                state.pool.`field`.clear()

          Box {.expand: false.}:
            orient = OrientX

            Label {.expand: false.}:
              text = "Search " & `asStr`
              xAlign = 0

            Entry:
              text = state.filter

          # TODO: https://github.com/can-lehmann/owlkettle-crud/blob/main/src/view/user_list.nim
