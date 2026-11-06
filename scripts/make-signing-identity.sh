#!/bin/zsh
# Sets up the self-signed code-signing identity tingjian.app is signed with, in a
# dedicated keychain. A stable identity keeps the app's designated requirement
# the same across builds, so macOS privacy grants (audio capture, mic) survive.
#
#   scripts/make-signing-identity.sh                 create it if missing (idempotent)
#   scripts/make-signing-identity.sh --force         replace it with a new one
#   scripts/make-signing-identity.sh --import FILE   install it from a .p12 (CI)
#
# A newly generated identity is also saved as a .p12 (password "tingjian") at
# $P12_OUT, so it can be stored as the SIGNING_P12_BASE64 secret for releases.
set -euo pipefail

NAME="tingjian local signing"
KEYCHAIN="$HOME/Library/Keychains/tingjian-signing.keychain-db"
PASS="tingjian"   # local-only keychain; holds nothing but this throwaway identity
P12_OUT="$HOME/Library/Application Support/tingjian/signing-identity.p12"

MODE=create
IMPORT_FILE=""
case "${1:-}" in
  --force) MODE=force ;;
  --import) MODE=import; IMPORT_FILE="${2:?usage: --import FILE}" ;;
  "") ;;
  *) echo "unknown option $1"; exit 2 ;;
esac

add_to_search_list() {
  # codesign only looks in keychains on the user search list.
  if ! security list-keychains -d user | grep -q tingjian-signing; then
    security list-keychains -d user -s $(security list-keychains -d user | tr -d '"') "$KEYCHAIN"
  fi
}

if [[ $MODE == create && -f "$KEYCHAIN" ]] && security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  add_to_search_list
  echo "Signing identity already exists in $KEYCHAIN"
  exit 0
fi

if [[ -f "$KEYCHAIN" ]]; then
  security delete-keychain "$KEYCHAIN"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [[ $MODE == import ]]; then
  P12="$IMPORT_FILE"
else
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
  P12="$TMP/id.p12"
  openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$P12" -passout pass:$PASS -name "$NAME" 2>/dev/null
  mkdir -p "${P12_OUT:h}"
  cp "$P12" "$P12_OUT"
  chmod 600 "$P12_OUT"
fi

security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # never auto-lock
security unlock-keychain -p "$PASS" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$KEYCHAIN" >/dev/null
add_to_search_list

echo "Installed signing identity '$NAME' in $KEYCHAIN"
[[ $MODE != import ]] && echo "Saved a copy for CI at $P12_OUT"
exit 0
