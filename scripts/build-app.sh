#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
case "${1:-}" in
  '') product=IslandMac; plist=Resources/App-Info.plist ;;
  --probe) product=IslandProbe; plist=Resources/Probe-Info.plist ;;
  *) echo 'Usage: scripts/build-app.sh [--probe]' >&2; exit 2 ;;
esac
swift build --build-system native --product "$product"
bin_dir=$(swift build --build-system native --show-bin-path)
app=".build/apps/$product.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/$product" "$app/Contents/MacOS/$product"
cp "$plist" "$app/Contents/Info.plist"
if [ "$product" = IslandMac ]; then
  swift scripts/export-localizations.swift Sources/IslandMac/Resources/Localizable.xcstrings "$app/Contents/Resources"
fi
codesign --force --sign - --identifier "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" "$app"
echo "$app"
