#!/bin/zsh
# A look at the helper's screen: the region x y w h in points (default: the whole screen), saved small in reviews/look/.
#   tools/look.sh NAME [X Y W H] [WIDTH]
here=${0:A:h}; out="$here/../reviews/look"; mkdir -p "$out"
shot=$(atlas screenshot | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["path"])')
x=${2:-0}; y=${3:-0}; w=${4:-2752}; h=${5:-1152}; width=${6:-1760}
ffmpeg -v error -y -i "$shot" -vf "crop=$((w*2)):$((h*2)):$((x*2)):$((y*2)),scale=$width:-1" "$out/$1.png"
echo "$out/$1.png"
