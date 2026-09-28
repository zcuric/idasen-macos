#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build/site
mkdir -p build/site
cp -R docs/. build/site/
cp tokens.css build/site/tokens.css
touch build/site/.nojekyll
printf 'Site built in build/site\n'
