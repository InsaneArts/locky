#!/usr/bin/env bash
# Renders a page of the Locky window to a PNG, without disturbing the screen: a second Locky opens the
# window behind every other window, and quits after the capture.
#
#   Scripts/window-shot.sh SECTION OUT.png [THEME]      # dashboard, themes, plugins, config, or settings
#
# SIZE (default 1240x780) is the window's content size; a tall one shows a long page whole.
# WAIT (seconds, default 4) is how long the page gets to load. Locky's config folder is an empty one with
# privacy mode on unless LOCKY_CONFIG_DIR names one, and the desktop picture is none unless LOCKY_WALLPAPER
# names one; photos after wrong passwords never show. Needs Locky.app built (Scripts/package_app.sh).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SECTION=${1:?usage: window-shot.sh SECTION OUT.png [THEME]}
OUT=${2:?usage: window-shot.sh SECTION OUT.png [THEME]}
BIN="$ROOT/Locky.app/Contents/MacOS/Locky"
[[ -x "$BIN" ]] || { echo "Build Locky.app first: Scripts/package_app.sh" >&2; exit 1; }

TOOL="$ROOT/.build/window-id"
[[ -x "$TOOL" && "$TOOL" -nt "$ROOT/Scripts/window-id.swift" ]] || swiftc -O -o "$TOOL" "$ROOT/Scripts/window-id.swift"

if [[ -z "${LOCKY_CONFIG_DIR:-}" ]]; then
  CONFIG=$(mktemp -d)
  echo '{ "privacy": true }' > "$CONFIG/settings.json"
else
  CONFIG=$LOCKY_CONFIG_DIR
fi
TITLE="$(tr '[:lower:]' '[:upper:]' <<< "${SECTION:0:1}")${SECTION:1}"
ARGS=(window "$SECTION" --behind --size "${SIZE:-1240x780}")
[[ -n "${3:-}" ]] && ARGS+=(--theme "$3")
LOCKY_CONFIG_DIR="$CONFIG" LOCKY_RESOURCES="$ROOT/Sources/Locky/Resources" LOCKY_WALLPAPER="${LOCKY_WALLPAPER:-none}" \
  "$BIN" "${ARGS[@]}" >/dev/null 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
ID=$("$TOOL" "$PID" "$TITLE") || { echo "No window titled $TITLE appeared" >&2; exit 1; }
sleep "${WAIT:-4}"
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
