\book {
  \bookOutputSuffix "$instrumentName"
  \score {
    \new ${staffPrefix}Staff \with {
      instrumentName = #"$instrumentName"
      midiInstrument = #"$midiInstrument"
    } {
      \autoLineBreaksOff
      \task
    }
    \midi {}
    \layout {
      ragged-right = ##t
    }
    \header {
      tagline = ##f
    }
  }
}
