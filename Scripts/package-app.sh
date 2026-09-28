#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/build-app.sh
ARCH="$(uname -m)"
ARCHIVE="build/Idasen-macOS-${ARCH}.zip"
codesign --verify --deep --strict build/Idasen.app
ditto -c -k --sequesterRsrc --keepParent build/Idasen.app "$ARCHIVE"
(cd build && shasum -a 256 "Idasen-macOS-${ARCH}.zip" > "Idasen-macOS-${ARCH}.zip.sha256")
printf 'Packaged %s (ad-hoc signed; not notarized)\n' "$ARCHIVE"
