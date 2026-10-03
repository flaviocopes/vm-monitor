#!/bin/sh
# Builds a universal (Apple silicon and Intel) dist/VM Monitor.app. It signs it with Flavio's
# Developer ID when that certificate is in the keychain, and ad hoc everywhere else (CI, forks).

set -eu

VERSION=1.0.0
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/VM Monitor.app"
CONTENTS="$APP/Contents"
ICON_SOURCE="$ROOT/Assets/AppIcon.png"
ICONSET="$ROOT/.build/AppIcon.iconset"

cd "$ROOT"
swift build -c release --arch arm64 --arch x86_64 --product VMMonitorApp

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/apple/Products/Release/VMMonitorApp" "$CONTENTS/MacOS/VM Monitor"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>VM Monitor</string>
  <key>CFBundleExecutable</key>
  <string>VM Monitor</string>
  <key>CFBundleIdentifier</key>
  <string>com.flaviocopes.vm-monitor</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>VM Monitor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

touch "$APP"
IDENTITY=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: Flavio Copes \(DGFKNTAG99\)"/ { print $2; exit }')
if [ -n "$IDENTITY" ]; then
  # Every Mach-O inside-out, then the app, without --deep.
  find "$APP" -depth -type f | while IFS= read -r file; do
    case $(file -b "$file") in
      *Mach-O*) codesign --force --options runtime --timestamp --sign "$IDENTITY" "$file" ;;
    esac
  done
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --strict "$APP"
else
  codesign --force --deep --sign - "$APP"
  codesign --verify --deep --strict "$APP"
fi
echo "$APP"
