#!/bin/bash
# Builds Wallflow.app and packages it as build/Wallflow.dmg (drag-to-Applications installer).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

STAGE="build/dmg"
DMG="build/Wallflow.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Wallflow.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Wallflow" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Created $DMG"
