from std/sets import incl, len
from std/strbasics import strip
import std/paths
import std/tempfiles

import owlkettle

import ../core




viewable TaskSnippetEditor:
  pool: TaskPool
  tasksnippet: TaskSnippet
  original: TaskSnippet

method view(editor: TaskSnippetEditorState): Widget = 
  gui:
    Grid:
      Label {.x: 0, y: 0.}:
        text = "Name"
        xAlign = 0 # Align left

      Entry {.x: 1, y: 0.}:
        text = editor.tasksnippet.name

        proc changed(text: string) =
          editor.tasksnippet.name = text

      Label {.x: 0, y: 1.}:
        text = "LilyPond Snippet Code"
        xAlign = 0 # Align left

      Entry {.x: 1, y: 1, hExpand: true.}:
        text = editor.tasksnippet.snippet
        placeholder = "LilyPond expression"

        proc changed(text: string) =
          editor.tasksnippet.snippet = text

      Label {.x: 0, y: 2.}:
        text = "Snippet Key"
        xAlign = 0 # Align left

      Entry {.x: 1, y: 2.}:
        text = editor.tasksnippet.key

        proc changed(text: string) =
          editor.tasksnippet.key = text

      Button {.x: 1, y: 3.}:
        text = if editor.original.isNil: "Create" else: "Update"
        style = [ButtonSuggested]

        proc clicked =
          strip(editor.tasksnippet.snippet)
          strip(editor.tasksnippet.key)

          if editor.tasksnippet.key == "":
            discard editor.open: gui:
              MessageDialog:
                message = "Snippet must have key"

                DialogButton {.addButton.}:
                  text = "Ok"
                  res = DialogAccept
            return

          if editor.tasksnippet.snippet == "":
            discard editor.open: gui:
              MessageDialog:
                message = "Lilypond snippet code cannot be blank"

                DialogButton {.addButton.}:
                  text = "Ok"
                  res = DialogAccept
            return

          try:
            editor.tasksnippet.name = normalizeName(editor.tasksnippet.name, editor.pool.nameRe)
          except ValueError:
            discard editor.open: gui:
              MessageDialog:
                message = "Error parsing snippet name: " & getCurrentExceptionMsg()

                DialogButton {.addButton.}:
                  text = "Ok"
                  res = DialogAccept
            return
          if editor.original.isNil:
            editor.tasksnippet.path = createTempDir("mus299-", "").Path
          else:
            editor.original.snippet = editor.tasksnippet.snippet
            editor.original.key = editor.tasksnippet.key
            editor.original.name = editor.tasksnippet.name

          if not editor.pool.resyncAll:
            if editor.pool.resync.len == 0:
              discard editor.redraw()
            editor.pool.resync.incl(editor.original)

          editor.respond(DialogResponse(kind: DialogAccept))

export TaskSnippetEditor, TaskSnippetEditorState
