#!/bin/sh
# Usage: scripts/package-release.sh X.Y.Z
set -eu
cd "$(dirname "$0")/.."
[ $# -eq 1 ] || { echo 'Usage: scripts/package-release.sh X.Y.Z' >&2; exit 2; }
version=$1
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Invalid version '$version': expected X.Y.Z" >&2; exit 2; }
scripts/build-app.sh --release --version "$version" >/dev/null
out=.build/release
zip_name="Notchent-$version.zip"
mkdir -p "$out"
rm -f "$out/$zip_name" "$out/$zip_name.sha256"
ditto -c -k --keepParent .build/apps/Notchent.app "$out/$zip_name"
(cd "$out" && shasum -a 256 "$zip_name" > "$zip_name.sha256")
echo "$out/$zip_name"
echo "$out/$zip_name.sha256"
