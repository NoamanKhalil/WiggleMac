#!/usr/bin/env bash
# Packages Wiggle as a DMG in build/release. Usage: scripts/release.sh [--local]
#
#   (no flag)  Distribution build: Developer ID signature, hardened runtime, notarized and
#              stapled. Notarization uploads the app to Apple; it uses the notarytool keychain
#              profile in WIGGLE_NOTARY_PROFILE (default "wiggle-notary"). With WIGGLE_FEED_URL,
#              also writes the Sparkle appcast for the update feed.
#   --local    Test build signed with the local identity. Fine on this Mac, but other Macs
#              will refuse to open it.
#
# Nothing is uploaded or hosted by this script: put the DMG and appcast.xml on your server yourself.
set -euo pipefail

MODE="release"
[ "${1:-}" = "--local" ] && MODE="local"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
APP="$ROOT/build/Wiggle.app"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
NOTARY_PROFILE="${WIGGLE_NOTARY_PROFILE:-wiggle-notary}"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
# Sparkle compares build numbers, so every release needs a higher one: the commit count works.
BUILD="$(git rev-list --count HEAD 2>/dev/null || /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)"
DMG="$OUT/Wiggle-$VERSION.dmg"

if [ "$MODE" = "release" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "warning: uncommitted changes; build $BUILD won't match a commit" >&2
fi

notarize() {
    echo "Notarizing $(basename "$1") (uploads it to Apple)…"
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

# 1. The app.
if [ "$MODE" = "release" ]; then
    WIGGLE_RELEASE=1 WIGGLE_BUILD_NUMBER="$BUILD" scripts/build-app.sh release
    ZIP="$(mktemp -d)/Wiggle.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    xcrun stapler staple "$APP"
else
    WIGGLE_BUILD_NUMBER="$BUILD" scripts/build-app.sh release
fi

# 2. The disk image: the app next to a shortcut to Applications.
mkdir -p "$OUT"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Wiggle.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Wiggle" -srcfolder "$STAGING" -fs APFS -format UDZO -o "$DMG"

if [ "$MODE" = "release" ]; then
    IDENTITY="${WIGGLE_DEVELOPER_ID:-$(security find-identity -v -p codesigning \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
fi
echo "Built $DMG (version $VERSION, build $BUILD)"

# 3. The update feed. generate_appcast signs each update with the "wiggle" key in the login
#    Keychain (macOS may ask to allow access the first time), or WIGGLE_ED_KEY_FILE.
if [ "$MODE" = "release" ] && [ -n "${WIGGLE_FEED_URL:-}" ]; then
    UPDATES="$OUT/updates"
    mkdir -p "$UPDATES"
    cp "$DMG" "$UPDATES/"
    KEY=(--account wiggle)
    [ -n "${WIGGLE_ED_KEY_FILE:-}" ] && KEY=(--ed-key-file "$WIGGLE_ED_KEY_FILE")
    PREFIX="${WIGGLE_DOWNLOAD_URL_PREFIX:-${WIGGLE_FEED_URL%/*}/}"
    "$SPARKLE_BIN/generate_appcast" "${KEY[@]}" --download-url-prefix "$PREFIX" -o "$UPDATES/appcast.xml" "$UPDATES"
    echo "Wrote $UPDATES/appcast.xml. Upload it to $WIGGLE_FEED_URL and the DMG under $PREFIX"
fi
