#!/usr/bin/env bash
# Builds Locky.app from the SwiftPM build. SIGNING_MODE: adhoc (default), dev, or release.
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=Locky
BUNDLE_ID=${BUNDLE_ID:-com.tornikegomareli.Locky}
SIGNING_MODE=${SIGNING_MODE:-adhoc}
APP_IDENTITY=${APP_IDENTITY:-}
source "$ROOT/version.env"

ARCH_FLAGS=()
for ARCH in ${ARCHES:-$(uname -m)}; do ARCH_FLAGS+=(--arch "$ARCH"); done
swift build -c "$CONF" "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c "$CONF" "${ARCH_FLAGS[@]}" --show-bin-path)"

APP="$ROOT/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp -R "$ROOT/Sources/$APP_NAME/Resources/." "$APP/Contents/Resources/"
xattr -cr "$APP"

if [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
  codesign --force --sign - "$APP"
elif [[ "$SIGNING_MODE" == "release" ]]; then
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" "$APP"
else
  codesign --force --options runtime --sign "$APP_IDENTITY" "$APP"
fi
echo "Built $APP"
