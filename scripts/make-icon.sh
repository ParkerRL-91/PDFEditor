#!/bin/bash
set -euo pipefail

ICONSET_DIR="Resources/AppIcon.iconset"
SOURCE_PNG="/tmp/pdfstack-icon-1024.png"

mkdir -p Resources
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift scripts/make-icon.swift "$SOURCE_PNG"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
