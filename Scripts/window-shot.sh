#!/usr/bin/env bash
# Renders a Locky window to a PNG, without disturbing the screen: a second Locky opens the window behind every
# other window, and quits after the capture.
#
#   Scripts/window-shot.sh SECTION OUT.png [THEME]      # themes, settings, plugins, config, or welcome
#
# themes is the Themes window (with THEME: Customize for it); settings, plugins, and config are the Settings
# window's panes; welcome is the Welcome window. The old names still work: dashboard is the Themes window, and
# widgets captures the Add Widget sheet alone, opened over Customize for the theme in use (or THEME).
#
# SIZE (default 1240x780) is the Themes window's content size; the Settings and Welcome windows have their own
# sizes. APPEARANCE=light or APPEARANCE=dark draws the window in that appearance (Locky reads it as
# LOCKY_APPEARANCE); without it, the Mac's own. WAIT (seconds, default 4) is how long the window gets to load.
# Locky's config folder is an empty one with privacy mode on unless LOCKY_CONFIG_DIR names one, and the desktop
# picture is none unless LOCKY_WALLPAPER names one; photos after wrong passwords never show. Needs Locky.app built
# (Scripts/package_app.sh). PAGE (1 to 3, default 1) is the Welcome's page.
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
  CONFIG=$(cd "$LOCKY_CONFIG_DIR" && pwd)
fi
ARGS=(window "$SECTION" --behind --size "${SIZE:-1240x780}")
[[ -n "${3:-}" ]] && ARGS+=(--theme "$3")
[[ -n "${PAGE:-}" ]] && ARGS+=(--page "$PAGE")
LOCKY_CONFIG_DIR="$CONFIG" LOCKY_RESOURCES="$ROOT/Sources/Locky/Resources" LOCKY_WALLPAPER="${LOCKY_WALLPAPER:-none}" \
  LOCKY_APPEARANCE="${APPEARANCE:-}" "$BIN" "${ARGS[@]}" >/dev/null 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
# Any titled window: the Themes window ("Themes", or the theme's name in Customize), the Settings window (its
# pane's name), or the Welcome.
ID=$("$TOOL" "$PID" "") || { echo "No Locky window appeared" >&2; exit 1; }
SHEET=""
if [[ $SECTION == widgets ]]; then
  SHEET=$("$TOOL" "$PID" "" --sheet "$ID") || echo "No Add Widget sheet appeared; capturing the window"
fi
sleep "${WAIT:-4}"
screencapture -x -o -l "$ID" "$OUT"
if [[ -n $SHEET ]]; then
  # macOS draws a sheet into the capture of its window, whichever of the two ids is captured. So the script crops
  # the window's image to the sheet's frame, read again after the wait, when the sheet no longer moves.
  read -r _ X Y W H WIDTH <<< "$("$TOOL" "$PID" "" --sheet "$ID")"
  SCALE=$(( $(sips -g pixelWidth "$OUT" | awk '/pixelWidth:/ { print $2 }') / WIDTH ))
  sips -c $((H * SCALE)) $((W * SCALE)) --cropOffset $((Y * SCALE)) $((X * SCALE)) "$OUT" >/dev/null
fi
echo "$OUT"
