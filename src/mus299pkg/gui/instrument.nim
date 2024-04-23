import std/sequtils

import owlkettle

import ../core
import ../performer


const
  instrumentNamesSeq = toSeq(instrumentNames)
  staffPrefixesSeq = toSeq(staffPrefixes)

viewable InstrumentEditor:
  pool: TaskPool
  instrument: Instrument
  original: Instrument
  selectedInstrumentInd {.private.}: int
  selectedPrefixInd {.private.}: int

  hooks:
    build:
      if not widget.valOriginal.isNil:
        state.selectedInstrumentInd = find(instrumentNamesSeq, widget.valOriginal.name)
        state.selectedPrefixInd = find(staffPrefixesSeq, widget.valOriginal.staffPrefix)

method view(editor: InstrumentEditorState): Widget = 
  gui:
    Grid:
      Label {.x: 0, y: 0.}:
        text = "MIDI Instrument"
        xAlign = 0 # Align left

      DropDown {.x: 1, y: 0.}:
        items = instrumentNamesSeq
        selected = editor.selectedInstrumentInd
        enableSearch = true

        proc select(item: int) =
          editor.selectedInstrumentInd = item

      Label {.x: 0, y: 1.}:
        text = "LilyPond Staff Prefix"
        xAlign = 0 # Align left

      DropDown {.x: 1, y: 1.}:
        items = staffPrefixesSeq
        selected = editor.selectedPrefixInd

        proc select(item: int) =
          editor.selectedPrefixInd = item

      Button {.x: 1, y: 2.}:
        text = if editor.original.isNil: "Create" else: "Update"
        style = [ButtonSuggested]

        proc clicked = 
          if editor.selectedInstrumentInd == -1:
            discard editor.open: gui:
              MessageDialog:
                message = "Must select MIDI instrument"

                DialogButton {.addButton.}:
                  text = "Ok"
                  res = DialogAccept
            return
          editor.instrument.name = instrumentNames[editor.selectedInstrumentInd]
          editor.instrument.staffPrefix = staffPrefixes[editor.selectedPrefixInd]
          if not editor.original.isNil:
            editor.original[] = editor.instrument[]
            if not editor.pool.resyncAll:
              editor.pool.resyncAll = true
              discard editor.redraw()
          editor.respond(DialogResponse(kind: DialogAccept))

export InstrumentEditor, InstrumentEditorState
