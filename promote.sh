#!/bin/sh


set -eu


PIDS="$(pgrep -x -u "$(logname)" gui|oneshot|fluidsynth|wireplumber|pipewire|pipewire-pulse)"
for i in $PIDS ; do
      renice -15 "$i"
      chrt -p 98 "$i"
done
