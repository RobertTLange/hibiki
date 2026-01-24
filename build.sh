#!/bin/bash
set -e

# Parse arguments
BUILD_DMG=false
RUN_APP=false
for arg in "$@"; do
    case $arg in
        --dmg) BUILD_DMG=true ;;
        --run) RUN_APP=true ;;
    esac
done

# Use release build for DMG, debug for regular builds
if [ "$BUILD_DMG" = true ]; then
    echo "Building Hibiki (release)..."
    swift build -c release
    EXECUTABLE=".build/release/Hibiki"
else
    echo "Building Hibiki..."
    swift build
    EXECUTABLE=".build/debug/Hibiki"
fi

APP_DIR=".build/Hibiki.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/Hibiki"

# Create app icon (convert PNG to ICNS)
ICONSET_DIR="$APP_DIR/Contents/Resources/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Generate all required icon sizes from the source PNG
sips -z 16 16     Sources/Hibiki/hibiki.png --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
sips -z 32 32     Sources/Hibiki/hibiki.png --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -z 32 32     Sources/Hibiki/hibiki.png --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
sips -z 64 64     Sources/Hibiki/hibiki.png --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -z 128 128   Sources/Hibiki/hibiki.png --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
sips -z 256 256   Sources/Hibiki/hibiki.png --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -z 256 256   Sources/Hibiki/hibiki.png --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
sips -z 512 512   Sources/Hibiki/hibiki.png --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -z 512 512   Sources/Hibiki/hibiki.png --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
sips -z 1024 1024 Sources/Hibiki/hibiki.png --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

# Convert iconset to icns
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"

# Copy resource bundles (for runtime resources)
BUILD_DIR=$(dirname "$EXECUTABLE")
if [ -d "$BUILD_DIR/Hibiki_Hibiki.bundle" ]; then
    cp -R "$BUILD_DIR/Hibiki_Hibiki.bundle" "$APP_DIR/Contents/Resources/"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Hibiki</string>
    <key>CFBundleIdentifier</key>
    <string>com.superlisten.hibiki</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Hibiki</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Hibiki needs accessibility permission to read selected text from other applications.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Codesign the app bundle (ad-hoc signing to seal resources)
codesign --force --deep --sign - "$APP_DIR"

echo "Built Hibiki.app at: $APP_DIR"

# Reset accessibility permission so it re-registers with the .app bundle (and its icon)
tccutil reset Accessibility com.superlisten.hibiki 2>/dev/null || true

# Create DMG if requested
if [ "$BUILD_DMG" = true ]; then
    echo "Creating DMG..."
    DMG_DIR=".build/dmg"
    DMG_PATH=".build/Hibiki.dmg"

    # Clean up any previous DMG build
    rm -rf "$DMG_DIR"
    rm -f "$DMG_PATH"

    # Create DMG staging directory
    mkdir -p "$DMG_DIR"
    cp -R "$APP_DIR" "$DMG_DIR/"
    ln -s /Applications "$DMG_DIR/Applications"

    # Create DMG
    hdiutil create -volname "Hibiki" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_PATH"

    # Clean up staging directory
    rm -rf "$DMG_DIR"

    echo "Created DMG at: $DMG_PATH"
fi

# Optionally launch
if [ "$RUN_APP" = true ]; then
    # Kill existing instances
    pkill -f "Hibiki.app" 2>/dev/null || true
    sleep 1
    open "$APP_DIR"
    echo "Hibiki.app launched"
fi
