#!/bin/bash
set -e

# Parse arguments
BUILD_DMG=false
RUN_APP=false
INSTALL_CLI=false
for arg in "$@"; do
    case $arg in
        --dmg) BUILD_DMG=true ;;
        --run) RUN_APP=true ;;
        --install) INSTALL_CLI=true ;;
    esac
done

# Use release build for DMG, debug for regular builds
if [ "$BUILD_DMG" = true ]; then
    echo "Building Hibiki (release)..."
    swift build -c release --product Hibiki
    EXECUTABLE=".build/release/Hibiki"
else
    echo "Building Hibiki..."
    swift build --product Hibiki
    EXECUTABLE=".build/debug/Hibiki"
fi

APP_DIR=".build/Hibiki.app"
# Ensure a clean app bundle so read-only resource files don't block rebuilds.
rm -rf "$APP_DIR"
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
for bundle in "$BUILD_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

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
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>Hibiki CLI</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>hibiki</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Codesign the app bundle (ad-hoc signing to seal resources)
codesign --force --deep --sign - "$APP_DIR"

echo "Built Hibiki.app at: $APP_DIR"

# Build CLI tool
echo "Building hibiki CLI..."

# Clean up any stray object files from SPM bug (object file outputs to cwd instead of build dir)
rm -f HibikiCLI.o main.o

if [ "$BUILD_DMG" = true ]; then
    BUILD_CONFIG="release"
    CLI_EXECUTABLE=".build/release/hibiki-cli"
else
    BUILD_CONFIG="debug"
    CLI_EXECUTABLE=".build/debug/hibiki-cli"
fi

swift build -c "$BUILD_CONFIG" --product hibiki-cli

# Clean up any remaining stray object files
rm -f HibikiCLI.o main.o

if [ ! -f "$CLI_EXECUTABLE" ]; then
    echo "Error: CLI executable not found at $CLI_EXECUTABLE"
    exit 1
fi

APP_INODE=$(stat -f '%i' "$EXECUTABLE" 2>/dev/null || true)
CLI_INODE=$(stat -f '%i' "$CLI_EXECUTABLE" 2>/dev/null || true)
if [ -n "$APP_INODE" ] && [ "$APP_INODE" = "$CLI_INODE" ]; then
    echo "Error: CLI executable collides with app executable path"
    echo "  App: $EXECUTABLE"
    echo "  CLI: $CLI_EXECUTABLE"
    exit 1
fi

# Copy CLI to app bundle's MacOS directory for easy access
cp "$CLI_EXECUTABLE" "$APP_DIR/Contents/MacOS/hibiki-cli"
echo "CLI tool available at: $CLI_EXECUTABLE"
echo "Also copied to: $APP_DIR/Contents/MacOS/hibiki-cli"

# Install CLI to /usr/local/bin if requested
if [ "$INSTALL_CLI" = true ]; then
    echo "Installing hibiki CLI to /usr/local/bin..."
    INSTALL_PATH="/usr/local/bin/hibiki"
    CLI_ABSOLUTE_PATH="$(cd "$(dirname "$CLI_EXECUTABLE")" && pwd)/$(basename "$CLI_EXECUTABLE")"

    # Try without sudo first
    if ln -sf "$CLI_ABSOLUTE_PATH" "$INSTALL_PATH" 2>/dev/null; then
        echo "CLI installed: $INSTALL_PATH -> $CLI_ABSOLUTE_PATH"
    else
        # Need sudo
        echo "Requires sudo to install to /usr/local/bin"
        sudo ln -sf "$CLI_ABSOLUTE_PATH" "$INSTALL_PATH"
        echo "CLI installed: $INSTALL_PATH -> $CLI_ABSOLUTE_PATH"
    fi
    echo "You can now run 'hibiki --help' from anywhere"
fi

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
