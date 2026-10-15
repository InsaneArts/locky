#!/usr/bin/env bash
# Builds Locky.app from the SwiftPM build. SIGNING_MODE: adhoc (default), dev, or release.
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=Locky
# A local signing.env (ignored by git) can set SIGNING_MODE and APP_IDENTITY for every build: with a certificate, macOS
# keeps permissions such as Accessibility across builds; an ad-hoc build is a new app to it each time.
if [[ -f "$ROOT/signing.env" ]]; then source "$ROOT/signing.env"; fi
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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSCameraUsageDescription</key><string>Locky takes a photo when someone enters too many wrong passwords, if you turn that on in Settings.</string>
    <key>NSLocationUsageDescription</key><string>Locky shows the weather where this Mac is, if you choose Current Location for a weather widget.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>Locky shows the weather where this Mac is, if you choose Current Location for a weather widget.</string>
</dict>
</plist>
PLIST

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# The guard, which locks the Mac if Locky dies or hangs during a lock. Locky finds it beside its executable.
cp "$BIN_DIR/locky-guard" "$APP/Contents/MacOS/locky-guard"
cp -R "$ROOT/Sources/$APP_NAME/Resources/." "$APP/Contents/Resources/"
# PermissionFlow's words (its .lproj tables). PermissionFlowResources looks in Bundle.main's Resources first. SwiftPM's
# Bundle.module would look in the app's root, where codesign does not allow files, and then in this Mac's .build, and
# stops the app if neither has it: PermissionFlow never calls it. A release build drops code that nothing calls, so the
# message of Bundle.module's stop in the binary means a new version calls it.
cp -R "$BIN_DIR/PermissionFlow_PermissionFlow.bundle" "$APP/Contents/Resources/"
# SwiftPM writes its tables read-only, and xattr below must clear them.
chmod -R u+w "$APP/Contents/Resources/PermissionFlow_PermissionFlow.bundle"
if [[ "$CONF" == "release" ]] && grep -q "could not load resource bundle" "$APP/Contents/MacOS/$APP_NAME"; then
  echo "ERROR: the binary calls SwiftPM's Bundle.module, which stops Locky.app when it runs on another Mac" >&2
  exit 1
fi
xattr -cr "$APP"

# The guard first, then the app that contains it. Every mode, ad-hoc too, signs with the hardened runtime, so
# DYLD_INSERT_LIBRARIES and other injected code cannot hook Locky or its guard. The runtime blocks the camera
# (intruder photos) and Location Services (the weather's Current Location) unless Locky.entitlements allows them.
if [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
  IDENTITY=- TIMESTAMP=--timestamp=none
elif [[ "$SIGNING_MODE" == "release" ]]; then
  IDENTITY=$APP_IDENTITY TIMESTAMP=--timestamp
else
  IDENTITY=$APP_IDENTITY TIMESTAMP=--timestamp=none
fi
codesign --force "$TIMESTAMP" --options runtime --sign "$IDENTITY" "$APP/Contents/MacOS/locky-guard"
codesign --force "$TIMESTAMP" --options runtime --entitlements "$ROOT/$APP_NAME.entitlements" --sign "$IDENTITY" "$APP"
echo "Built $APP"

# Install the build in /Applications, where Launch at Login expects a stable path. INSTALL=0 skips it.
if [[ "${INSTALL:-1}" == "1" ]]; then
  DEST="${INSTALL_DIR:-/Applications}/$APP_NAME.app"
  if rm -rf "$DEST" && ditto "$APP" "$DEST"; then
    echo "Installed $DEST"
  else
    echo "WARN: could not install $DEST; the build is at $APP" >&2
  fi
fi
