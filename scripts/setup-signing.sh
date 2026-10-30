#!/usr/bin/env bash
# Creates a self-signed "Wiggle Local Signing" identity in its own keychain
# (~/Library/Keychains/wiggle-signing.keychain-db). Signing every build with the
# same identity lets macOS remember Screen Recording, Microphone and Keychain
# permissions across rebuilds. Remove with: security delete-keychain wiggle-signing.keychain-db
set -euo pipefail

NAME="Wiggle Local Signing"
KEYCHAIN="$HOME/Library/Keychains/wiggle-signing.keychain-db"
PASS="wiggle-local"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -f "$KEYCHAIN" ]; then
    echo "Signing keychain already exists: $KEYCHAIN"
    exit 0
fi

cat > "$TMP/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.conf" 2>/dev/null
# SHA1/3DES: the only PKCS#12 encryption macOS's `security import` accepts.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -name "$NAME" -out "$TMP/id.p12" -passout pass:"$PASS" 2>/dev/null

security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # never auto-lock
security unlock-keychain -p "$PASS" "$KEYCHAIN"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$KEYCHAIN" >/dev/null

echo "Created signing identity \"$NAME\" in $KEYCHAIN"
