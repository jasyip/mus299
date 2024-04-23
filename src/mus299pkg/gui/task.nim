import std/enumerate
from std/sugar import collect
from std/sequtils import toSeq
from std/strutils import strip
from std/sets import items, contains, incl, excl, len
from std/tables import withValue

import owlkettle

import ../core
import ../task
import ../pool

viewable TaskEditor:
  pool: TaskPool
  task: Task
  original: Task
  snippetInd {.private.}: int
  snippets {.private.}: seq[TaskSnippet]
  snippetAddrs {.private.}: seq[string]
  tasks {.private.}: seq[Task]
  curCategory {.private.}: string
  addToPool {.private.}: bool
  invalidCategoryLabel {.private.}: string

  hooks:
    build:
      state.snippetInd = -1
      state.snippets = toSeq(widget.valPool.tasksnippets.items)
      state.snippetAddrs = collect:
        for (i, snippet) in enumerate(state.snippets):
          if snippet == widget.valTask.snippet:
            state.snippetInd = i
          snippet.name
      state.tasks = collect:
        for task in widget.valPool.tasks.items:
          if task != widget.valOriginal:
            task

method view(editor: TaskEditorState): Widget = 
  gui:
    Box:
      orient = OrientY
      Grid:
        Label {.x: 0, y: 0.}:
          text = "Snippet memory address"
          xAlign = 0 # Align left

        DropDown {.x: 1, y: 0, hExpand: true.}:
          items = editor.snippetAddrs
          selected = editor.snippetInd
          enableSearch = true

          proc select(itemIndex: int) =
            editor.task.snippet = editor.snippets[itemIndex]
            editor.snippetInd = itemIndex

        Label {.x: 0, y: 1.}:
          text = "Task dependencies"
          xAlign = 0 # Align left

        ScrolledWindow {.x: 1, y: 1, hExpand: true.}:
          ListBox:
            for task in editor.tasks:
              Box:
                orient = OrientX

                Label:
                  text = task.snippet.name & " | " & hexAddr(task)
                  xAlign = 0

                CheckButton {.expand: false.}:
                  state = task in editor.task.depends

                  proc changed(state: bool) =
                    if state:
                      editor.task.depends.incl(task)
                    else:
                      editor.task.depends.excl(task)

        Label {.x: 0, y: 2.}:
          text = "Categories"
          xAlign = 0 # Align left

        Box {.x: 1, y: 2.}:
          orient = OrientY

          Entry {.expand: false.}:
            text = editor.curCategory
            placeholder = "Category"

            proc changed(text: string) =
              editor.curCategory = text

            proc activate() =
              try:
                editor.task.allowedCategories.incl(normalizeName(editor.curCategory, editor.pool.nameRe).Category)
              except ValueError:
                editor.invalidCategoryLabel = "Please make your category more simple: " & editor.curCategory
                return

              editor.invalidCategoryLabel = ""
              editor.curCategory = ""

          ScrolledWindow {.expand: false.}:
            ListBox:
              for category in editor.task.allowedCategories:
                Box:
                  orient = OrientX

                  Label:
                    text = category.string
                    xAlign = 0

                  Button {.expand: false.}:
                    icon = "user-trash-symbolic"
                    proc clicked() =
                      editor.task.allowedCategories.excl(category)

        Label {.x: 0, y: 3.}:
          text = "Add to Pool?"
          xAlign = 0 # Align left

        CheckButton {.x: 1, y: 3.}:
          state = editor.addToPool

          proc changed(state: bool) =
            editor.addToPool = state

      Label:
        text = editor.invalidCategoryLabel

      Button:
        text = if editor.original.isNil: "Create" else: "Update"
        style = [ButtonSuggested]

        proc clicked =
          if editor.task.snippet.isNil:
            discard editor.open: gui:
              MessageDialog:
                message = "Must select snippet"

                DialogButton {.addButton.}:
                  text = "Ok"
                  res = DialogAccept
            return

          if editor.task.allowedCategories.len == 0:
            discard editor.open: gui:
              MessageDialog:
                message = "Must have at least 1 category"

                DialogButton {.addButton.}:
                  text = "Ok"
                  res = DialogAccept
            return

          if editor.original.isNil:
            for parent in editor.task.depends:
              parent.dependents.incl(editor.task)
          else:
            try:
              editor.original.changeDependencies(editor.task.depends)
            except ValueError:
              discard editor.open: gui:
                MessageDialog:
                  message = "Error changing task dependencies: " & getCurrentExceptionMsg()

                  DialogButton {.addButton.}:
                    text = "Ok"
                    res = DialogAccept
              return
            editor.original.snippet = editor.task.snippet
            editor.original.allowedCategories = editor.task.allowedCategories
            editor.task = editor.original

          if editor.addToPool:
            editor.pool.addTask(editor.task)
          else:
            for category in editor.task.allowedCategories.items:
              editor.pool.pool.withValue(category, v):
                v[].excl(editor.task)
          editor.respond(DialogResponse(kind: DialogAccept))

export TaskEditor, TaskEditorState
