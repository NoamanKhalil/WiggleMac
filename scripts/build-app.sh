#!/usr/bin/env bash
# Builds Wiggle.app into ./build. Usage: scripts/build-app.sh [debug|release]
#
# Signing: with WIGGLE_RELEASE=1, signs for distribution with a "Developer ID Application"
# certificate (or WIGGLE_DEVELOPER_ID), the hardened runtime and a secure timestamp.
# Otherwise signs with the local identity from scripts/setup-signing.sh, or ad-hoc.
#
# Optional: WIGGLE_FEED_URL turns on update checks (Sparkle's SUFeedURL);
# WIGGLE_BUILD_NUMBER sets CFBundleVersion.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Wiggle.app"
ENTITLEMENTS="$ROOT/Resources/Wiggle.entitlements"

cd "$ROOT"
swift build -c "$CONFIG" --arch arm64
BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Wiggle" "$APP/Contents/MacOS/Wiggle"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Sparkle, for automatic updates. ditto keeps the framework's symlinks intact.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Wiggle"

PLIST="$APP/Contents/Info.plist"
if [ -n "${WIGGLE_FEED_URL:-}" ]; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $WIGGLE_FEED_URL" "$PLIST"
fi
if [ -n "${WIGGLE_BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $WIGGLE_BUILD_NUMBER" "$PLIST"
fi

# Signs Sparkle's helpers inside-out, then the app. "$@" says which identity and options.
sign_app() {
    local fw="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
    codesign --force "$@" "$fw/XPCServices/Installer.xpc"
    codesign --force "$@" --preserve-metadata=entitlements "$fw/XPCServices/Downloader.xpc"
    codesign --force "$@" "$fw/Autoupdate"
    codesign --force "$@" "$fw/Updater.app"
    codesign --force "$@" "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force "$@" --entitlements "$ENTITLEMENTS" "$APP"
}

if [ "${WIGGLE_RELEASE:-0}" = "1" ]; then
    IDENTITY="${WIGGLE_DEVELOPER_ID:-$(security find-identity -v -p codesigning \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
    if [ -z "$IDENTITY" ]; then
        echo "error: no \"Developer ID Application\" certificate in your keychain; see Releasing in README.md" >&2
        exit 1
    fi
    sign_app --sign "$IDENTITY" --options runtime --timestamp
    echo "Signed for distribution with: $IDENTITY"
else
    # A stable identity keeps macOS permissions (Screen Recording, Microphone,
    # Keychain) across rebuilds; see scripts/setup-signing.sh. Ad-hoc otherwise.
    KEYCHAIN="$HOME/Library/Keychains/wiggle-signing.keychain-db"
    IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
        | awk '/"Wiggle Local Signing"/ { print $2; exit }')"
    if [ -n "$IDENTITY" ]; then
        security unlock-keychain -p wiggle-local "$KEYCHAIN"
        sign_app --keychain "$KEYCHAIN" --sign "$IDENTITY"
    else
        echo "warning: no local signing identity; run scripts/setup-signing.sh to keep permissions across rebuilds"
        sign_app --sign -
    fi
fi
codesign --verify --strict "$APP"
echo "Built $APP"
