#!/bin/sh
# Usage: scripts/install-app.sh [--destination DIR] [--no-open]
set -eu
cd "$(dirname "$0")/.."
dest=/Applications; open_after=1
while [ $# -gt 0 ]; do
  case "$1" in
    --destination) [ $# -ge 2 ] || { echo 'Missing value for --destination' >&2; exit 2; }; dest=$2; shift ;;
    --no-open) open_after=0 ;;
    *) echo 'Usage: scripts/install-app.sh [--destination DIR] [--no-open]' >&2; exit 2 ;;
  esac
  shift
done
dest=${dest%/}
[ -n "$dest" ] || dest=/
if [ -L "$dest" ]; then echo "Refusing symlinked destination: $dest" >&2; exit 1; fi
[ -d "$dest" ] || mkdir -p "$dest"
dest=$(cd "$dest" && pwd -P)
target="$dest/Notchent.app"
new="$dest/.Notchent.app.new"
backup="$dest/.Notchent.app.old.$$"

scripts/build-app.sh --release >/dev/null
src=.build/apps/Notchent.app

# Any running Notchent (installed or a development build) must quit first: two copies would
# both attach a panel to the notch. Quitting goes through the app, so it can confirm open terminals.
running_pids() { pgrep -f '/Notchent\.app/Contents/MacOS/IslandMac$' 2>/dev/null || true; }
if [ -n "$(running_pids)" ]; then
  echo 'Notchent is running; asking it to quit...'
  osascript -e 'quit app "Notchent"' >/dev/null 2>&1 || true
  i=0
  while [ -n "$(running_pids)" ] && [ "$i" -lt 20 ]; do sleep 1; i=$((i + 1)); done
  if [ -n "$(running_pids)" ]; then
    echo "Notchent is still running after 20s. Quit it and retry." >&2
    exit 1
  fi
fi

rm -rf "$new"
restore() {
  rm -rf "$new"
  if [ -d "$backup" ] && [ ! -e "$target" ]; then mv "$backup" "$target"; fi
}
trap restore EXIT
ditto "$src" "$new"
if [ -e "$target" ]; then mv "$target" "$backup"; fi
mv "$new" "$target"
rm -rf "$backup"
trap - EXIT

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$target/Contents/Info.plist")
if [ "$open_after" = 1 ]; then open "$target"; fi
echo "Installed: $target (version $version)"
