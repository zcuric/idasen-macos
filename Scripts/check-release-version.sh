#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?Pass a tag such as v1.0.0}"
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release tags must use vMAJOR.MINOR.PATCH (for example, v1.0.0)." >&2
  exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
if [[ "$TAG" != "v$VERSION" ]]; then
  echo "Tag $TAG does not match Info.plist version $VERSION." >&2
  exit 1
fi
printf 'Release version %s matches Info.plist\n' "$TAG"
