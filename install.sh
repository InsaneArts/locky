#!/bin/sh
# Installs the latest Locky, a lock screen for the Mac with themes and widgets written in Lua.
#
#   curl -fsSL https://raw.githubusercontent.com/InsaneArts/locky/main/install.sh | sh
#
# It reads the release that Locky's update feed lists, checks that Apple notarized the app and that Locky's
# developer signed it, and copies it to /Applications, or to ~/Applications if /Applications is not writable.
# LOCKY_INSTALL_DIR picks another folder. Later updates come through Locky itself.
#
# Everything runs inside main, so a download cut short runs nothing.

FEED="${LOCKY_FEED:-https://github.com/InsaneArts/locky/releases/latest/download/appcast.xml}"
TEAM_ID="539293JFA3"   # the same as TEAM_ID in Scripts/release.sh

say() { printf '%s\n' "$*"; }
fail() { printf 'Locky was not installed: %s\n' "$*" >&2; exit 1; }

main() {
  set -eu
  [ "$(uname -s)" = Darwin ] || fail "Locky runs on macOS only."
  [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 15 ] || fail "Locky needs macOS 15 or later."

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  # The feed lists the newest release first.
  curl -fsSL "$FEED" -o "$tmp/appcast.xml" || fail "Locky has no release at $FEED yet."
  url=$(sed -n 's/.*url="\([^"]*\.zip\)".*/\1/p' "$tmp/appcast.xml" | head -n 1)
  version=$(sed -n 's/.*<sparkle:shortVersionString>\(.*\)<\/sparkle:shortVersionString>.*/\1/p' "$tmp/appcast.xml" | head -n 1)
  [ -n "$url" ] || fail "the update feed lists no download."

  say "Downloading Locky ${version:-}…"
  curl -fL --progress-bar "$url" -o "$tmp/Locky.zip" || fail "the download from $url failed."
  ditto -x -k "$tmp/Locky.zip" "$tmp/unzipped" || fail "the download is not a valid zip."
  app="$tmp/unzipped/Locky.app"
  [ -d "$app" ] || fail "the download has no Locky.app."

  # Check the signature and notarization before anything is copied.
  codesign --verify --deep --strict "$app" 2>/dev/null || fail "the app's signature does not check out."
  team=$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  [ "$team" = "$TEAM_ID" ] || fail "the app is signed by team ${team:-none}, not by Locky's developer ($TEAM_ID)."
  spctl --assess --type execute "$app" 2>/dev/null || fail "Gatekeeper rejects the app: Apple has not notarized it."

  dest="${LOCKY_INSTALL_DIR:-/Applications}"
  if [ -z "${LOCKY_INSTALL_DIR:-}" ] && [ ! -w "$dest" ]; then dest="$HOME/Applications"; fi
  mkdir -p "$dest" || fail "Locky cannot write to $dest."
  if pgrep -f "^$dest/Locky.app/Contents/MacOS/Locky" >/dev/null 2>&1; then
    fail "Locky is running from $dest. Quit it from its menu bar icon, then run this again."
  fi
  rm -rf "$dest/Locky.app.old"
  if [ -d "$dest/Locky.app" ]; then mv "$dest/Locky.app" "$dest/Locky.app.old"; fi
  if ditto "$app" "$dest/Locky.app"; then
    rm -rf "$dest/Locky.app.old"
  else
    rm -rf "$dest/Locky.app"
    if [ -d "$dest/Locky.app.old" ]; then mv "$dest/Locky.app.old" "$dest/Locky.app"; fi
    fail "Locky could not be copied to $dest."
  fi

  say "Locky ${version:-} is in $dest. Open it from there, or with Spotlight."
}

main "$@"
