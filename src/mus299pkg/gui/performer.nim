import std/sequtils
from std/strbasics import strip
import std/sets
from std/sugar import collect
import std/enumerate
import std/math

import ../../owlkettle/owlkettle

import ../core




viewable PerformerEditor:
  pool: TaskPool
  performer: Performer
  original: Performer
  instrumentInd {.private.}: int
  instruments {.private.}: seq[Instrument]
  instrumentNames {.private.}: seq[string]
  curCategory {.private.}: string
  invalidCategoryLabel {.private.}: string
  channelFloat {.private.}: float

  hooks instruments:
    build:
      state.instruments = toSeq(widget.valPool.instruments.items)

  hooks:
    afterBuild:
      state.instrumentInd = -1
      state.instrumentNames = collect:
        for (i, instrument) in enumerate(state.instruments):
          if instrument == widget.valPerformer.instrument:
            state.instrumentInd = i
          instrument.name
      discard state.redraw()

method view(editor: PerformerEditorState): Widget = 
  gui:
    Box:
      orient = OrientY
      Grid:
        Label {.x: 0, y: 0.}:
          text = "Name"
          xAlign = 0 # Align left

        Entry {.x: 1, y: 0.}:
          text = editor.performer.name

          proc changed(text: string) =
            editor.performer.name = text

        Label {.x: 0, y: 1.}:
          text = "Instrument"
          xAlign = 0 # Align left

        DropDown {.x: 1, y: 1, hExpand: true.}:
          items = editor.instrumentNames
          selected = editor.instrumentInd
          enableSearch = true

          proc select(itemIndex: int) =
            editor.performer.instrument = editor.instruments[itemIndex]
            editor.instrumentInd = itemIndex

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
                editor.performer.categories.incl(normalizeName(editor.curCategory, editor.pool.nameRe).Category)
              except ValueError:
                editor.invalidCategoryLabel = "Please make your category more simple: " & editor.curCategory
                return

              editor.invalidCategoryLabel = ""
              editor.curCategory = ""

          ScrolledWindow {.expand: false.}:
            ListBox:
              for category in editor.performer.categories:
                Box:
                  orient = OrientX

                  Label:
                    text = category.string
                    xAlign = 0

                  Button {.expand: false.}:
                    icon = "user-trash-symbolic"
                    proc clicked() =
                      editor.performer.categories.excl(category)

        Label {.x: 0, y: 3.}:
          text = "Minimum MIDI volume"
          xAlign = 0 # Align left

        SpinButton {.x: 1, y: 3.}:
          digits = 2
          value = editor.performer.minVolume
          max = 1.0
          stepIncrement = 0.05
          pageIncrement = 0.2

          proc valueChanged(value: float) =
            editor.performer.minVolume = value
            editor.performer.maxVolume = max(editor.performer.minVolume,
                                             editor.performer.maxVolume,
                                            )

        Label {.x: 0, y: 4.}:
          text = "Maximum MIDI volume"
          xAlign = 0 # Align left

        SpinButton {.x: 1, y: 4.}:
          digits = 2
          value = editor.performer.maxVolume
          max = 1.0
          stepIncrement = 0.05
          pageIncrement = 0.2

          proc valueChanged(value: float) =
            editor.performer.maxVolume = value
            editor.performer.minVolume = min(editor.performer.minVolume,
                                             editor.performer.maxVolume,
                                            )

        Label {.x: 0, y: 5.}:
          text = "Perfomer Key"
          xAlign = 0 # Align left

        Entry {.x: 1, y: 5.}:
          text = editor.performer.key
          placeholder = "pitch mode"

          proc changed(text: string) =
            editor.performer.key = text

        Label {.x: 0, y: 6.}:
          text = "Perfomer Clef"
          xAlign = 0 # Align left

        Entry {.x: 1, y: 6.}:
          text = editor.performer.clef

          proc changed(text: string) =
            editor.performer.clef = text

        Label {.x: 0, y: 7.}:
          text = "MIDI Channel"
          xAlign = 0 # Align left
  
        SpinButton {.x: 1, y: 7.}:
          digits = 0
          value = editor.channelFloat
          max = 15.0
          wrap = true
          stepIncrement = 1.0
  
          proc valueChanged(value: float) =
            editor.channelFloat = value

      Label:
        text = editor.invalidCategoryLabel

      Button:
        text = if editor.original.isNil: "Create" else: "Update"
        style = [ButtonSuggested]

        proc clicked =

          strip(editor.performer.key)
          strip(editor.performer.clef)

          if editor.performer.instrument.isNil:
            discard editor.open: gui:
              MessageDialog:
                message = "Must select instrument"

                DialogButton {.addButton.}:
                  text = "Ok"
                  res = DialogAccept
            return

          if editor.performer.categories.len == 0:
            discard editor.open: gui:
              MessageDialog:
                message = "Must have at least 1 category"

                DialogButton {.addButton.}:
                  text = "Ok"
                  res = DialogAccept
            return

          editor.channelFloat = if editor.performer.instrument.staffPrefix == "Drum":
                                  9.0
                                else:
                                  round(editor.channelFloat)

          if editor.performer.instrument.staffPrefix != "Drum" and almostEqual(editor.channelFloat, 9.0):
            discard editor.open: gui:
              MessageDialog:
                message = "(0-based) MIDI channel # cannot be 9"

                DialogButton {.addButton.}:
                  text = "Ok"
                  res = DialogAccept
            return
          editor.performer.channel = cast[uint](editor.channelFloat)


          try:
            editor.performer.name = normalizeName(editor.performer.name, editor.pool.nameRe)
          except ValueError:
            discard editor.open: gui:
              MessageDialog:
                message = "Error parsing performer name: " & getCurrentExceptionMsg()

                DialogButton {.addButton.}:
                  text = "Ok"
                  res = DialogAccept
            return


          if not editor.original.isNil:
            editor.original[] = editor.performer[]
          if not editor.pool.resyncAll:
            editor.pool.resyncAll = true
            discard editor.redraw()
          editor.respond(DialogResponse(kind: DialogAccept))

export PerformerEditor, PerformerEditorState
