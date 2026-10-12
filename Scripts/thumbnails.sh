#!/usr/bin/env bash
# Renders the built-in themes' thumbnails (Sources/Locky/Resources/thumbnails/<id>.jpg) for the Locky
# window. Nothing personal goes into them: privacy mode is on and no desktop picture shows.
#
#   Scripts/thumbnails.sh [THEME ...]      # default: every built-in theme
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/Sources/Locky/Resources/thumbnails"
mkdir -p "$OUT"
CONFIG=$(mktemp -d)
echo '{ "privacy": true }' > "$CONFIG/settings.json"
TMP=$(mktemp -d)
trap 'rm -rf "$CONFIG" "$TMP"' EXIT
CROP="$ROOT/.build/crop-image"
[[ -x "$CROP" && "$CROP" -nt "$ROOT/Scripts/crop-image.swift" ]] || swiftc -O -o "$CROP" "$ROOT/Scripts/crop-image.swift"
THEMES=("$@")
if [[ ${#THEMES[@]} -eq 0 ]]; then
  THEMES=(default)
  for dir in "$ROOT"/Sources/Locky/Resources/packages/*/themes/*.lua; do THEMES+=("$(basename "$dir" .lua)"); done
fi
for theme in "${THEMES[@]}"; do
  LOCKY_CONFIG_DIR="$CONFIG" LOCKY_WALLPAPER=none WAIT=${WAIT:-5} "$ROOT/Scripts/snapshot.sh" "$theme" "$TMP/$theme.png" >/dev/null
  # Cut the preview window's title bar (the content is the bottom 900 points) and its rounded corners.
  height=$(sips -g pixelHeight "$TMP/$theme.png" | awk '/pixelHeight/ { print $2 }')
  width=$(sips -g pixelWidth "$TMP/$theme.png" | awk '/pixelWidth/ { print $2 }')
  "$CROP" "$TMP/$theme.png" "$OUT/$theme.jpg" $(( height - width * 900 / 1440 )) $(( width / 120 )) 480
  echo "$OUT/$theme.jpg"
done
