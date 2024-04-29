\book {
  \bookOutputSuffix "$outputSuffix"
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
      \context {
        \Staff
        \remove "Staff_performer"
      }
      \context {
        \Voice
        \consists "Staff_performer"
      }
    }
    \layout {
      ragged-right = ##t
    }
    \header {
      tagline = ##f
    }
  }
}
