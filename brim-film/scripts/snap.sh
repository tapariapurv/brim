#!/bin/zsh
# usage: snap.sh 1,2,3 out.jpg : stills at those times as one 3-wide contact sheet
npx hyperframes snapshot --at "$1" >/dev/null 2>&1
d=.hyperframes/artifacts/snapshots; n=$(ls -t $d | head -1)
ffmpeg -v error -y -pattern_type glob -i "$d/$n/frame-*.png" -frames:v 1 -vf "scale=640:-2,tile=3x4" -q:v 3 "$2"; echo done
