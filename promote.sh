#!/bin/sh


set -eu


PIDS="$(pgrep -x -u "$(logname)" "fluidsynth|wireplumber|pipewire|pw-data-loop|alsa-midi-seq|SDLAudioP2")"
for i in $PIDS ; do
      renice -15 "$i"
      chrt -p 98 "$i"
done
PIDS="$(pgrep -x -u "$(logname)" "gui|oneshot")"
for i in $PIDS ; do
      renice -12 "$i"
      chrt -p 60 "$i"
done
