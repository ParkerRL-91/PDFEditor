#!/bin/bash
set -euo pipefail

APP_NAME="PDF Stack"
APP_DIR="dist/${APP_NAME}.app"
DMG_PATH="dist/${APP_NAME}.dmg"
DMG_LOG="/tmp/pdfstack-dmg.log"
STAGING_DIR="$(mktemp -d)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/build-app.sh"

echo "Building ${DMG_PATH}..."
rm -f "$DMG_PATH"

cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

if ! hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" > "$DMG_LOG" 2>&1; then
  echo "DMG creation failed. See $DMG_LOG"
  rm -rf "$STAGING_DIR"
  exit 1
fi

rm -rf "$STAGING_DIR"

echo "Built ${DMG_PATH}"
echo "Open it with: open \"${DMG_PATH}\""
