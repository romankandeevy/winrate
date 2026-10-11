#!/bin/bash
# Рисует Resources/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")/.."
SET="$(mktemp -d)/AppIcon.iconset"
swift tools/make-icon.swift "$SET"
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$SET/icon_512x512@2x.png" /tmp/counter-trade-icon.png
echo "==> Resources/AppIcon.icns"
