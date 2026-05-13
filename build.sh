#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Tokade"
EXEC_NAME="Tokade"
BUNDLE_ID="com.bjamba.tokade"
APP_DIR="${APP_NAME}.app"

echo "→ swift build -c release"
swift build -c release

echo "→ Assembling ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/${EXEC_NAME}" "$APP_DIR/Contents/MacOS/${EXEC_NAME}"

# Copy SPM-processed resource bundle (e.g. menu bar icon) into Resources/.
# Bundle.module's lookup checks main.resourceURL first, which is this folder.
RES_BUNDLE_NAME="${EXEC_NAME}_Tokade.bundle"
if [ -d ".build/release/${RES_BUNDLE_NAME}" ]; then
    cp -R ".build/release/${RES_BUNDLE_NAME}" "$APP_DIR/Contents/Resources/${RES_BUNDLE_NAME}"
fi

# App icon.
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${EXEC_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "→ Ad-hoc codesign"
# Don't use --deep: the SPM resource bundle has no Info.plist and isn't a real
# bundle for signing purposes. Sign the executable, then the app, individually.
codesign --force --sign - "$APP_DIR/Contents/MacOS/${EXEC_NAME}" >/dev/null
codesign --force --sign - "$APP_DIR" >/dev/null

echo "✓ Built: $APP_DIR"
echo "  Run:    open \"$APP_DIR\""
