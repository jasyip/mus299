import core

type
  # Only channel 10 (9 when 0-based)
  PercussionistObj* = object of PerformerObj
    note*: uint8  # General MIDI
  Percussionist* = ref PercussionistObj

  PitchedObj* = object of PerformerObj
    program*: int8  # Also General MIDI, 0 -> Grand Piano, etc.
  Pitched* = ref PitchedObj
