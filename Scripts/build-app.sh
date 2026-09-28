#!/usr/bin/env bash
#
# Assembles a double-clickable Idasen.app bundle from the SwiftPM executable.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="${APP_NAME:-Idasen}"
CONFIG="${CONFIG:-release}"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"

echo "==> Building ${APP_NAME} (${CONFIG})"
swift build -c "${CONFIG}" --product "${APP_NAME}"

BIN_PATH="$(swift build -c "${CONFIG}" --product "${APP_NAME}" --show-bin-path)"

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp "${BIN_PATH}/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"
cp Resources/Info.plist "${CONTENTS}/Info.plist"

if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "${CONTENTS}/Resources/AppIcon.icns"
fi

/usr/libexec/PlistBuddy -c "Print" "${CONTENTS}/Info.plist" >/dev/null

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "${APP_DIR}"

echo "==> Done: ${APP_DIR}"
