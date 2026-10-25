#!/bin/sh
set -eu
[ "${1:-}" = "--probe" ] || { echo 'Usage: scripts/build-app.sh --probe' >&2; exit 2; }
cd "$(dirname "$0")/.."
swift build --build-system native --product IslandProbe
bin_dir=$(swift build --build-system native --show-bin-path)
app=.build/apps/IslandProbe.app
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/IslandProbe" "$app/Contents/MacOS/IslandProbe"
cp Resources/Probe-Info.plist "$app/Contents/Info.plist"
echo "$app"
