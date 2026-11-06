#!/bin/zsh
# Builds tingjian.app from the SwiftPM product (Command Line Tools only).
#
#   scripts/bundle.sh            release build → build/tingjian.app
#   scripts/bundle.sh --debug    debug build
#   scripts/bundle.sh --run      build, then (re)launch the app
set -euo pipefail
cd "${0:A:h}/.."

CONFIG=release
RUN=0
for arg in "$@"; do
  case $arg in
    --debug) CONFIG=debug ;;
    --run) RUN=1 ;;
    *) echo "unknown option $arg"; exit 2 ;;
  esac
done

BUNDLE_ID="com.pedroslopez.tingjian"
APP="build/tingjian.app"
# Version: $VERSION, else the latest v* tag, else 0.1.0.
if [[ -z "${VERSION:-}" ]]; then
  VERSION=$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null || true)
  VERSION=${VERSION#v}
  VERSION=${VERSION:-0.1.0}
fi
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)

swift build -c "$CONFIG" --product tingjian
BIN="$(swift build -c "$CONFIG" --show-bin-path)/tingjian"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/tingjian"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>tingjian</string>
  <key>CFBundleDisplayName</key><string>tingjian 听见</string>
  <key>CFBundleExecutable</key><string>tingjian</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>26.4</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAudioCaptureUsageDescription</key>
  <string>tingjian listens to audio playing on your Mac to show live Mandarin → English subtitles. Audio is processed on-device and never stored.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>tingjian can also listen to your microphone to subtitle nearby Mandarin speech. Audio is processed on-device and never stored.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>tingjian transcribes Mandarin speech on-device to translate it.</string>
</dict>
</plist>
PLIST

# Sign with the stable local identity (see make-signing-identity.sh) so privacy
# grants survive rebuilds; fall back to ad hoc if it's missing.
KEYCHAIN="$HOME/Library/Keychains/tingjian-signing.keychain-db"
IDENTITY="tingjian local signing"
if [[ -f "$KEYCHAIN" ]]; then
  scripts/make-signing-identity.sh >/dev/null   # ensures it's on the search list
  security unlock-keychain -p tingjian "$KEYCHAIN"
  HASH=$(security find-certificate -c "$IDENTITY" -Z "$KEYCHAIN" | awk '/SHA-1/{print $3}')
  codesign --force --sign "$HASH" --identifier "$BUNDLE_ID" "$APP"
else
  echo "warning: no local signing identity (run scripts/make-signing-identity.sh); signing ad hoc," \
       "so permission grants will reset on every build" >&2
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi
codesign -d -r- "$APP" 2>&1 | grep designated || true
echo "Built $APP"

if (( RUN )); then
  pkill -x tingjian 2>/dev/null && sleep 0.5 || true
  open "$APP"
fi
