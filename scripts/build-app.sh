#!/bin/bash
set -euo pipefail

APP_NAME="PDF Stack"
EXECUTABLE_NAME="PDFStack"
BUNDLE_ID="com.parkerlachance.pdfstack"
BUILD_LOG="/tmp/pdfstack-build.log"
APP_DIR="dist/${APP_NAME}.app"

echo "Building ${EXECUTABLE_NAME} (release)..."
if ! swift build -c release > "$BUILD_LOG" 2>&1; then
  echo "Build failed. See $BUILD_LOG"
  exit 1
fi

echo "Assembling ${APP_DIR}..."
rm -rf "dist"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp ".build/release/${EXECUTABLE_NAME}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
else
  echo "Warning: Resources/AppIcon.icns not found (run scripts/make-icon.sh first). The app will use a default icon."
fi

echo "Built ${APP_DIR}"
echo "Run it with: open \"${APP_DIR}\""
