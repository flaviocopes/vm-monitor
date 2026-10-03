#!/bin/sh
# Builds the universal app, notarizes it when it's signed with the Developer ID, staples the ticket,
# checks the signature survives zipping, and writes dist/VM-Monitor-<version>.zip for a GitHub release.
# Notarizing needs the Developer ID certificate in the keychain and a notarytool profile named "notary":
#   xcrun notarytool store-credentials notary --apple-id <apple id> --team-id DGFKNTAG99
# Usage: Scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/^ *static let version = "\(.*\)"$/\1/p' Sources/VMMonitorApp/Version.swift)
APP="$ROOT/dist/VM Monitor.app"
ZIP="$ROOT/dist/VM-Monitor-$VERSION.zip"
CHECK=$(mktemp -d)
trap 'rm -rf "$CHECK"' EXIT

rm -f "$ZIP"
Scripts/build-app.sh >/dev/null
lipo "$APP/Contents/MacOS/VM Monitor" -verify_arch arm64 x86_64

TEAM=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
if [ "$TEAM" = DGFKNTAG99 ]; then
  SIGNATURE="Developer ID"
  ditto -c -k --keepParent "$APP" "$ZIP"
  RESULT=$(xcrun notarytool submit "$ZIP" --keychain-profile notary --wait --output-format json)
  if [ "$(printf '%s' "$RESULT" | plutil -extract status raw -o - -)" != Accepted ]; then
    printf '%s\n' "$RESULT" >&2
    xcrun notarytool log "$(printf '%s' "$RESULT" | plutil -extract id raw -o - -)" --keychain-profile notary >&2
    exit 1
  fi
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
else
  SIGNATURE="ad-hoc"
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/VM Monitor.app"

echo "Built $ZIP, $SIGNATURE signed"
shasum -a 256 "$ZIP"
