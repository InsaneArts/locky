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
# Updates: Sparkle reads this feed, the appcast on the latest GitHub release, and installs a new Locky only if its
# EdDSA signature matches this public key. The private key is in the login Keychain of the Mac that makes the
# releases (docs/release.md).
FEED_URL="https://github.com/InsaneArts/locky/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="xRquHeubqKcUa++dWEyUOfpepj6X+4Jz6juNcf3tYfs="

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
    <key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
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
# Sparkle, for updates, without the headers a build needs. Locky finds it by the run path added here: SwiftPM's own
# points beside the executable.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$SPARKLE"
rm -rf "$SPARKLE"/{Headers,PrivateHeaders,Modules} "$SPARKLE"/Versions/B/{Headers,PrivateHeaders,Modules}
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/$APP_NAME" \
  2> >(grep -v "invalidate the code signature" >&2)
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

# macOS draws an app's windows by the SDK its binary names: Liquid Glass from 26 on, the look of macOS 15 before. SwiftPM
# writes the deployment target there instead of the SDK it built with, so Locky's windows kept the old look beside apps
# built in Xcode. The binary names the SDK that built it. Before signing: this changes the binary.
BIN="$APP/Contents/MacOS/$APP_NAME"
MINOS=$(xcrun vtool -show-build "$BIN" | awk '/minos/ { print $2; exit }')
xcrun vtool -set-build-version macos "$MINOS" "$(xcrun --show-sdk-version)" -replace -output "$BIN" "$BIN" \
  2> >(grep -v "code signature will be invalid" >&2)

# Sparkle's helpers and the guard first, then the app that contains them. Every mode, ad-hoc too, signs with the
# hardened runtime, so DYLD_INSERT_LIBRARIES and other injected code cannot hook Locky or its guard. The runtime blocks
# the camera (intruder photos) and Location Services (the weather's Current Location) unless Locky.entitlements allows
# them.
ENTITLEMENTS="$ROOT/$APP_NAME.entitlements"
if [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
  IDENTITY=- TIMESTAMP=--timestamp=none
  # The hardened runtime loads a library only if Apple or the app's own team signed it, and an ad-hoc signature has no
  # team: Locky would not start with Sparkle inside. An ad-hoc build alone turns that one check off.
  ENTITLEMENTS="$ROOT/.build/adhoc.entitlements"
  cp "$ROOT/$APP_NAME.entitlements" "$ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS"
elif [[ "$SIGNING_MODE" == "release" ]]; then
  IDENTITY=$APP_IDENTITY TIMESTAMP=--timestamp
else
  IDENTITY=$APP_IDENTITY TIMESTAMP=--timestamp=none
fi
SIGN=(codesign --force "$TIMESTAMP" --options runtime --sign "$IDENTITY")
# Inside out, as Sparkle's documentation signs them. The downloader keeps its own entitlements.
"${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" "$APP/Contents/MacOS/locky-guard"
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
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
