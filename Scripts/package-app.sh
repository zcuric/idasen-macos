#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/build-app.sh
ARCH="$(uname -m)"
PACKAGE="Idasen-macOS-${ARCH}"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/idasen-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

codesign --verify --deep --strict build/Idasen.app
ditto build/Idasen.app "$STAGING/Idasen.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -ov -srcfolder "$STAGING" -volname Idasen -fs HFS+ -format UDZO "build/$PACKAGE.dmg"
ditto -c -k --sequesterRsrc --keepParent build/Idasen.app "build/$PACKAGE.zip"

(
    cd build
    shasum -a 256 "$PACKAGE.dmg" > "$PACKAGE.dmg.sha256"
    shasum -a 256 "$PACKAGE.zip" > "$PACKAGE.zip.sha256"
)
printf 'Packaged %s.dmg and %s.zip (ad-hoc signed; not notarized)\n' "$PACKAGE" "$PACKAGE"
