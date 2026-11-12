#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
usage() { echo 'Usage: scripts/build-app.sh [--probe] [--release] [--version X.Y.Z]' >&2; exit 2; }
probe=0; config=debug; version=''
while [ $# -gt 0 ]; do
  case "$1" in
    --probe) probe=1 ;;
    --release) config=release ;;
    --version)
      [ $# -ge 2 ] || usage
      version=$2; shift
      printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Invalid version '$version': expected X.Y.Z" >&2; exit 2; }
      ;;
    *) usage ;;
  esac
  shift
done
if [ "$probe" = 1 ]; then
  product=IslandProbe; app_name=IslandProbe; plist=Resources/Probe-Info.plist
else
  product=IslandMac; app_name=Notchent; plist=Resources/App-Info.plist
fi
if [ "$config" = release ]; then
  set -- -c release
else
  set --
fi
swift build --build-system native "$@" --product "$product"
bin_dir=$(swift build --build-system native "$@" --show-bin-path)
app=".build/apps/$app_name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/$product" "$app/Contents/MacOS/$product"
cp "$plist" "$app/Contents/Info.plist"
if [ -n "$version" ]; then
  build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
fi
if [ "$product" = IslandMac ]; then
  swift build --build-system native "$@" --product IslandHook
  cp "$bin_dir/IslandHook" "$app/Contents/MacOS/IslandHook"
  codesign --force --sign - --identifier dev.nativeisland.hook "$app/Contents/MacOS/IslandHook"
  swift scripts/export-localizations.swift Sources/IslandMac/Resources/Localizable.xcstrings "$app/Contents/Resources"
  # SwiftTerm is statically linked; its MIT notice must accompany the app.
  mkdir -p "$app/Contents/Resources/ThirdPartyNotices"
  cp -f .build/checkouts/SwiftTerm/LICENSE "$app/Contents/Resources/ThirdPartyNotices/SwiftTerm-LICENSE.txt"
fi
codesign --force --sign - --identifier "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" "$app"
echo "$app"
