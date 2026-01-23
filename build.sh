#!/bin/bash
set -e

echo "Building Hibiki..."
swift build

APP_DIR=".build/Hibiki.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp .build/debug/Hibiki "$APP_DIR/Contents/MacOS/Hibiki"

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
if [ -d ".build/debug/Hibiki_Hibiki.bundle" ]; then
    cp -R .build/debug/Hibiki_Hibiki.bundle "$APP_DIR/Contents/Resources/"
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

# Optionally launch
if [ "$1" == "--run" ]; then
    # Kill existing instances
    pkill -f "Hibiki.app" 2>/dev/null || true
    sleep 1
    open "$APP_DIR"
    echo "Hibiki.app launched"
fi
