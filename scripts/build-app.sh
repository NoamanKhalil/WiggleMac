#!/usr/bin/env bash
# Builds Wiggle.app into ./build. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Wiggle.app"

cd "$ROOT"
swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Wiggle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Wiggle"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# A stable identity keeps macOS permissions (Screen Recording, Microphone,
# Keychain) across rebuilds; see scripts/setup-signing.sh. Ad-hoc otherwise.
KEYCHAIN="$HOME/Library/Keychains/wiggle-signing.keychain-db"
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
    | awk '/"Wiggle Local Signing"/ { print $2; exit }')"
if [ -n "$IDENTITY" ]; then
    security unlock-keychain -p wiggle-local "$KEYCHAIN"
    codesign --force --keychain "$KEYCHAIN" --sign "$IDENTITY" "$APP"
else
    echo "warning: no local signing identity; run scripts/setup-signing.sh to keep permissions across rebuilds"
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
