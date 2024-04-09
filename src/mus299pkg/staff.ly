\book {
  \bookOutputSuffix "$instrumentName"
  \score {
    \new ${staffPrefix}Staff \with {
      instrumentName = #"$instrumentName"
      midiInstrument = #"$midiInstrument"
    } {
      \task
    }
    \midi {}
    \layout {}
    \header {
      tagline = ##f
    }
  }
}
