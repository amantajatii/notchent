#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# CLT 6.4 ships Swift Testing outside the default SwiftPM framework search path.
frameworks="$(xcode-select -p)/Library/Developer/Frameworks"
swift test --build-system native --disable-xctest \
  -Xswiftc -F -Xswiftc "$frameworks" \
  -Xlinker -rpath -Xlinker "$frameworks" "$@"
