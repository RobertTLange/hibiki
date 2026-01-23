#!/bin/bash
set -e

echo "Building Hibiki..."
swift build

APP_DIR=".build/Hibiki.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp .build/debug/Hibiki "$APP_DIR/Contents/MacOS/Hibiki"

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

echo "Built Hibiki.app at: $APP_DIR"

# Optionally launch
if [ "$1" == "--run" ]; then
    # Kill existing instances
    pkill -f "Hibiki.app" 2>/dev/null || true
    sleep 1
    open "$APP_DIR"
    echo "Hibiki.app launched"
fi
