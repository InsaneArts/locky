#!/usr/bin/env bash
# Renders a theme's lock screen to a PNG, from the source tree, without disturbing the screen: the preview
# window opens behind every other window and closes after the capture.
#
#   Scripts/snapshot.sh THEME OUT.png [WIDTHxHEIGHT]      # default 1440x900
#
# WAIT (seconds, default 4) is how long the theme gets to draw. Locky's config folder is an empty one unless
# LOCKY_CONFIG_DIR names one, so your own init.lua never changes the result. Needs Locky.app built once
# (Scripts/package_app.sh); Lua, theme, and shader edits need no rebuild.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
THEME=${1:?usage: snapshot.sh THEME OUT.png [WxH]}
OUT=${2:?usage: snapshot.sh THEME OUT.png [WxH]}
SIZE=${3:-1440x900}
BIN="$ROOT/Locky.app/Contents/MacOS/Locky"
[[ -x "$BIN" ]] || { echo "Build Locky.app first: Scripts/package_app.sh" >&2; exit 1; }

TOOL="$ROOT/.build/window-id"
[[ -x "$TOOL" && "$TOOL" -nt "$ROOT/Scripts/window-id.swift" ]] || swiftc -O -o "$TOOL" "$ROOT/Scripts/window-id.swift"

CONFIG=${LOCKY_CONFIG_DIR:-$(mktemp -d)}
LOCKY_CONFIG_DIR="$CONFIG" LOCKY_RESOURCES="$ROOT/Sources/Locky/Resources" \
  "$BIN" preview --theme "$THEME" --size "$SIZE" --behind >/dev/null 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
ID=$("$TOOL" "$PID") || { echo "No preview window appeared" >&2; exit 1; }
sleep "${WAIT:-4}"
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
