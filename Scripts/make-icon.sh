#!/usr/bin/env bash
#
# Generates Resources/AppIcon.icns from Scripts/make-icon.swift.
#
set -euo pipefail

cd "$(dirname "$0")/.."

swift Scripts/make-icon.swift
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
