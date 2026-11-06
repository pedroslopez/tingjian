#!/bin/zsh
# Creates a self-signed code-signing identity in a dedicated keychain so that
# tingjian.app keeps the same designated requirement across rebuilds, and
# macOS privacy grants (audio capture, mic, speech) survive. Idempotent.
set -euo pipefail

NAME="tingjian local signing"
KEYCHAIN="$HOME/Library/Keychains/tingjian-signing.keychain-db"
PASS="tingjian"   # local-only keychain; holds nothing but this throwaway identity

if [[ -f "$KEYCHAIN" ]] && security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  if ! security list-keychains -d user | grep -q tingjian-signing; then
    security list-keychains -d user -s $(security list-keychains -d user | tr -d '"') "$KEYCHAIN"
  fi
  echo "Signing identity already exists in $KEYCHAIN"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
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
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout pass:$PASS -name "$NAME" 2>/dev/null

[[ -f "$KEYCHAIN" ]] || security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # never auto-lock
security unlock-keychain -p "$PASS" "$KEYCHAIN"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$KEYCHAIN" >/dev/null

# codesign only looks in keychains on the user search list.
if ! security list-keychains -d user | grep -q tingjian-signing; then
  security list-keychains -d user -s $(security list-keychains -d user | tr -d '"') "$KEYCHAIN"
fi

echo "Created signing identity '$NAME' in $KEYCHAIN"
