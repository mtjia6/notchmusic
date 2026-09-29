#!/bin/zsh
# Builds NotchMusic.app, signs it, and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/NotchMusic.app
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchMusic "$APP/Contents/MacOS/NotchMusic"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"

# Sign with a stable identity so macOS keeps the Automation permission across
# rebuilds (ad-hoc signatures change every build, which resets the grant).
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --options runtime --entitlements NotchMusic.entitlements --sign "${IDENTITY:--}" "$APP"

mkdir -p ~/Applications
pkill -x NotchMusic 2>/dev/null || true
rm -rf ~/Applications/NotchMusic.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/NotchMusic.app"
