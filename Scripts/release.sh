#!/usr/bin/env bash
# Makes a release of Locky: a universal Locky.app signed with the Developer ID, notarized and stapled, as
# dist/Locky-<version>.zip, with dist/appcast.xml, the update feed. Both are signed for Sparkle.
#
#   Scripts/release.sh             # build, sign, notarize, and package: publishes nothing
#   Scripts/release.sh --publish   # the same, then the tag, the GitHub release, and the Homebrew cask
#
# The version comes from version.env, and the notes from releases/<version>.md. docs/release.md has the steps.
#
# Environment:
#   NOTARY_PROFILE   notarytool keychain profile  (default: camus-notary)
#   SIGN_IDENTITY    Developer ID identity        (default: Developer ID Application: Techzy LLC (539293JFA3))
#   SPARKLE_ACCOUNT  Sparkle key in the Keychain  (default: Locky)
#   DEVELOPER_DIR    toolchain                    (default: /Applications/Xcode.app, the release Xcode; never a beta)
set -euo pipefail

PUBLISH=false
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=true ;;
    *) echo "usage: Scripts/release.sh [--publish]" >&2; exit 1 ;;
  esac
done

# The release Xcode links against the current SDK. A beta toolchain may write an SDK that Apple's notary refuses.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Locky"
TEAM_ID="539293JFA3"   # the same as TEAM_ID in install.sh
NOTARY_PROFILE="${NOTARY_PROFILE:-camus-notary}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Techzy LLC ($TEAM_ID)}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-Locky}"
REPO="InsaneArts/locky"
REPO_URL="https://github.com/$REPO"
TAP="InsaneArts/homebrew-tap"
DIST="$ROOT/dist"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

source "$ROOT/version.env"
VERSION="$MARKETING_VERSION"
TAG="v$VERSION"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
NOTES="$ROOT/releases/$VERSION.md"

# --- Preflight -------------------------------------------------------------
step "Preflight for $VERSION (build $BUILD_NUMBER) with $(xcrun swift --version 2>&1 | head -1 | sed 's/.*Apple Swift/Swift/')"
# With pipefail, `command | grep -q` fails when grep exits before the command ends. So the text goes to a variable.
IDENTITIES="$(security find-identity -v -p codesigning)"
[[ "$IDENTITIES" == *"$SIGN_IDENTITY"* ]] || fail "signing identity not found: $SIGN_IDENTITY"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || fail "notarytool profile '$NOTARY_PROFILE' not found. Store it one time with:
    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <apple-id> --team-id $TEAM_ID --password <app-specific-password>"
[[ -s "$NOTES" ]] || fail "write the release notes first: releases/$VERSION.md. Sparkle shows them in the update window"
if $PUBLISH; then
  gh auth status >/dev/null 2>&1 || fail "gh is not signed in: run 'gh auth login'"
  [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "a release is made from main"
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail "commit your changes first: the tag must name what was built"
  git rev-parse "$TAG" >/dev/null 2>&1 && fail "tag $TAG exists. Raise MARKETING_VERSION and BUILD_NUMBER in version.env"
  # Sparkle offers a release only if its build number is higher than the installed one's.
  LAST="$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null || true)"
  if [[ -n "$LAST" ]]; then
    LAST_BUILD="$(git show "$LAST:version.env" 2>/dev/null | sed -n 's/^BUILD_NUMBER=//p')"
    [[ -z "$LAST_BUILD" || "$BUILD_NUMBER" -gt "$LAST_BUILD" ]] || fail "BUILD_NUMBER $BUILD_NUMBER is not higher than $LAST's ($LAST_BUILD)"
  fi
fi
echo "  identity, notary profile, and release notes are ready"

step "Tests"
swift test 2>&1 | tail -3

# --- Build and sign --------------------------------------------------------
step "Build a universal app and sign it with the Developer ID"
SIGNING_MODE=release APP_IDENTITY="$SIGN_IDENTITY" ARCHES="arm64 x86_64" INSTALL=0 "$ROOT/Scripts/package_app.sh" release 2>&1 | grep -v "replacing existing signature"
APP="$ROOT/$APP_NAME.app"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for code in "$SPARKLE/Versions/B/XPCServices/Installer.xpc" "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
            "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE" "$APP/Contents/MacOS/locky-guard" "$APP"; do
  INFO="$(codesign -dvv "$code" 2>&1)"
  [[ "$INFO" == *"TeamIdentifier=$TEAM_ID"* ]] || fail "$(basename "$code") is not signed by team $TEAM_ID"
  [[ "$INFO" == *"runtime"* ]] || fail "$(basename "$code") has no hardened runtime"
  [[ "$INFO" == *"Timestamp="* ]] || fail "$(basename "$code") has no secure timestamp"
done
# Only an ad-hoc build may load libraries of another team (package_app.sh).
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
[[ "$ENTITLEMENTS" != *"disable-library-validation"* ]] || fail "the release build turns library validation off"
for binary in "$APP/Contents/MacOS/$APP_NAME" "$APP/Contents/MacOS/locky-guard"; do
  ARCHS="$(lipo -archs "$binary")"
  [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || fail "$(basename "$binary") is not universal: $ARCHS"
done
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$BUILT" == "$VERSION" ]] || fail "the built app reports version '$BUILT', not $VERSION"
echo "  $(lipo -archs "$APP/Contents/MacOS/$APP_NAME"), version $BUILT ($BUILD_NUMBER), team $TEAM_ID"

step "Sparkle key and feed"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || fail "Sparkle's tools are missing from $SPARKLE_BIN"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
[[ "$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)" == "$PUBLIC_KEY" ]] \
  || fail "the Keychain's Sparkle key (account $SPARKLE_ACCOUNT) does not match SPARKLE_PUBLIC_KEY in Scripts/package_app.sh"
FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist")"
[[ "$FEED" == "$REPO_URL/releases/latest/download/appcast.xml" ]] || fail "unexpected SUFeedURL: $FEED"
echo "  key $PUBLIC_KEY, feed $FEED"

# --- Notarize --------------------------------------------------------------
step "Notarize with profile '$NOTARY_PROFILE' (this takes a few minutes)"
rm -rf "$DIST" && mkdir -p "$DIST"
/usr/bin/ditto --norsrc -c -k --keepParent "$APP" "$DIST/notarize.zip"
NOTARY_LOG="$(xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
echo "$NOTARY_LOG" | grep -E "id:|status:" | tail -2 | sed 's/^/  /'
[[ "$NOTARY_LOG" == *"status: Accepted"* ]] || fail "notarization failed. See: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"
rm "$DIST/notarize.zip"

step "Staple and verify"
xcrun stapler staple "$APP" >/dev/null
xcrun stapler validate "$APP" >/dev/null || fail "the staple ticket is not valid"
spctl -a -t exec -vv "$APP" 2>&1 | sed 's/^/  /'
spctl -a -t exec "$APP" || fail "Gatekeeper rejects the app"

/usr/bin/ditto --norsrc -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "  $(basename "$ZIP")  sha256 $SHA"

# --- Appcast ---------------------------------------------------------------
# The feed goes on the GitHub release beside the zip. SUFeedURL and install.sh read it from the latest release.
step "Appcast for $VERSION, signed with the Keychain key '$SPARKLE_ACCOUNT'"
UPDATES="$DIST/updates"
mkdir -p "$UPDATES"
cp "$ZIP" "$UPDATES/"
cp "$NOTES" "$UPDATES/$APP_NAME-$VERSION.md"
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" --maximum-deltas 0 \
  --download-url-prefix "$REPO_URL/releases/download/$TAG/" --link "$REPO_URL" --embed-release-notes \
  -o "$DIST/appcast.xml" "$UPDATES"
rm -rf "$UPDATES"
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$DIST/appcast.xml"
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$DIST/appcast.xml" || fail "the appcast's signature does not verify"
SIGNATURE="$(xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$DIST/appcast.xml")"
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$ZIP" "$SIGNATURE" || fail "the zip's signature in the appcast does not verify"
echo "  appcast.xml lists $(basename "$ZIP") at $REPO_URL/releases/download/$TAG/"

if ! $PUBLISH; then
  step "Done. Nothing was published. To publish this build's version: Scripts/release.sh --publish"
  exit 0
fi

# --- Publish ---------------------------------------------------------------
step "Tag $TAG and publish the GitHub release"
git tag -a "$TAG" -m "$APP_NAME $VERSION"
git push -q origin main "$TAG"
gh release create "$TAG" "$ZIP" "$DIST/appcast.xml" --repo "$REPO" --title "$APP_NAME $VERSION" --notes-file "$NOTES"

step "Point the Homebrew cask at $VERSION"
TAP_DIR="$(mktemp -d)"
trap 'rm -rf "$TAP_DIR"' EXIT
gh repo clone "$TAP" "$TAP_DIR" -- -q --depth 1
# Scripts/locky.rb is the cask, with places for the version and the zip's checksum.
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" "$ROOT/Scripts/locky.rb" > "$TAP_DIR/Casks/locky.rb"
git -C "$TAP_DIR" add Casks/locky.rb
git -C "$TAP_DIR" commit -q -m "locky $VERSION"
git -C "$TAP_DIR" push -q
echo "  $TAP: Casks/locky.rb is at $VERSION"

step "Check what people will download"
FOUND="$(curl -fsSL "$REPO_URL/releases/latest/download/appcast.xml" | sed -n 's/.*<sparkle:shortVersionString>\(.*\)<\/sparkle:shortVersionString>.*/\1/p' | head -n 1)"
[[ "$FOUND" == "$VERSION" ]] || fail "the feed at $REPO_URL/releases/latest/download/appcast.xml lists '$FOUND', not $VERSION"
echo "  the feed lists $VERSION"
step "Done: $(gh release view "$TAG" --repo "$REPO" --json url -q .url)"
