#!/bin/sh
# Renders docs/screenshot-light.png and docs/screenshot-dark.png (the Live view), and docs/chat-light.png
# and docs/chat-dark.png (a chat with a command open), from the real views, in the test VM.
# It compiles the app's sources with Scripts/screenshot.swift in place of the @main file, into an app with
# its own bundle ID. Then it copies a made-up history from Scripts/sample-activity.py into the VM, runs the
# app there, copies the images back and removes what it added.
# The Live view shows the VM's screen as it is now, or the image you pass. The history's screenshots use
# <App>.png from the folder you pass, or the screen. Another agent's app can be on the VM's screen, so pass
# images of apps that are already public.
# Usage: Scripts/screenshot.sh [screen.png] [folder of <App>.png window shots]
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TESTVM=$(command -v testvm) || { echo "Install testvm first: https://github.com/flaviocopes/testvm" >&2; exit 1; }
BUILD="$ROOT/.build/screenshot"
APP="$BUILD/VM Monitor Screenshot.app"
REMOTE=/tmp/vm-monitor-screenshot
TARGET=arm64-apple-macos15
FLAGS="-O -swift-version 6 -parse-as-library -target $TARGET"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" docs
# The views import MonitorCore, so it becomes a library first.
swiftc $FLAGS -module-name MonitorCore -emit-module -emit-module-path "$BUILD/MonitorCore.swiftmodule" \
  -emit-library -static -o "$BUILD/libMonitorCore.a" Sources/MonitorCore/*.swift
find Sources/VMMonitorApp -name '*.swift' ! -exec grep -q '^@main' {} \; -exec \
  swiftc $FLAGS -I "$BUILD" -L "$BUILD" -lMonitorCore -o "$APP/Contents/MacOS/Screenshot" Scripts/screenshot.swift {} +

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Screenshot</string>
  <key>CFBundleIdentifier</key>
  <string>com.flaviocopes.vm-monitor.screenshot</string>
  <key>CFBundleName</key>
  <string>VM Monitor Screenshot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"

python3 Scripts/sample-activity.py "$BUILD/sample" >/dev/null
if [ -n "${1:-}" ]; then cp "$1" "$BUILD/screen.png"; else "$TESTVM" shot "" "$BUILD/screen.png" >/dev/null; fi
mkdir -p "$BUILD/images"
while IFS="$(printf '\t')" read -r app file; do
  shot="${2:-/nonexistent}/$app.png"
  [ -f "$shot" ] || shot="$BUILD/screen.png"
  cp "$shot" "$BUILD/images/$(basename "$file")"
done < "$BUILD/sample/images.txt"

"$TESTVM" run "rm -rf $REMOTE ~/Library/Logs/testvm && mkdir -p $REMOTE /tmp/testvm"
"$TESTVM" push "$BUILD/images/" /tmp/testvm/
"$TESTVM" push "$BUILD/screen.png" "$REMOTE/screen.png"
for folder in Library/Logs/testvm .cursor .claude .codex; do
  "$TESTVM" push "$BUILD/sample/$folder/" "$folder/"
done

"$TESTVM" open "$APP" "$REMOTE" "$REMOTE/screen.png" -AppleLocale en_US -AppleLanguages '(en)' >/dev/null
"$TESTVM" run 'while pgrep -f "VM Monitor Screenshot.app/Contents/MacOS" >/dev/null; do sleep 1; done'
for image in screenshot-light screenshot-dark chat-light chat-dark; do
  "$TESTVM" pull "$REMOTE/$image.png" docs/
done

# testvm keeps its own screenshots on this Mac, so /tmp/testvm in the VM only holds the ones pushed above.
"$TESTVM" run "rm -rf $REMOTE /tmp/testvm ~/Library/Logs/testvm ~/.claude/projects/-Users-flavio-dev-noterepo \
  ~/.cursor/projects/Users-flavio-dev-skillscout/agent-transcripts/7c1e2a4b-5d3f-4e8a-9b6c-1f2e3d4c5b6a \
  ~/Apps/'VM Monitor Screenshot.app' ~/Apps/'VM Monitor Screenshot.log'; \
  find ~/.codex/sessions -name '*01a3f2c4-8b1d-7e20-9c4a-5f6e7d8c9b0a*' -delete 2>/dev/null; true"
ls -la docs/screenshot-*.png docs/chat-*.png
