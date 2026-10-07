#!/bin/bash
# Creates a free, self-signed code-signing identity "SmartNotch Signing" in the login keychain.
# Why: an ad-hoc signature changes on every build, so macOS forgets permission grants
# (Accessibility, Camera) after each update. A stable certificate keeps the app's
# "designated requirement" the same across builds, so grants stick. Gatekeeper behaves the same
# as ad-hoc (users still click "Open Anyway" once). This is NOT an Apple Developer ID.
# Keep a backup of this identity (Keychain Access → export). Losing it only means users re-grant once.
set -euo pipefail
NAME="SmartNotch Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "'$NAME' already exists"; exit 0; fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="$(/usr/bin/openssl rand -hex 16)"   # one-time transport password for the .p12, never shown
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PASS" 2>/dev/null
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "Created '$NAME' in your login keychain."
