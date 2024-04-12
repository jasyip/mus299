\book {
  \bookOutputSuffix "$instrumentName"
  \score {
    \new ${staffPrefix}Staff \with {
      instrumentName = #"$instrumentName"
      midiInstrument = #"$midiInstrument"
      $properties
    } {
      \autoLineBreaksOff
      $task
    }
    \midi {
      $tempo
    }
    \layout {
      ragged-right = ##t
    }
    \header {
      tagline = ##f
    }
  }
}
