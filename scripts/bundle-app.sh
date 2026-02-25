#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="KTApple"

# Defaults
VERSION=""
CREATE_DMG=false

usage() {
    echo "Usage: $0 [--version <version>] [--dmg]"
    echo ""
    echo "  --version <version>  Set CFBundleShortVersionString (default: read from Info.plist)"
    echo "  --dmg                Create a DMG disk image"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --dmg)
            CREATE_DMG=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "==> Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release

# Locate the executable
EXECUTABLE=".build/arm64-apple-macosx/release/$APP_NAME"
if [[ ! -f "$EXECUTABLE" ]]; then
    echo "Error: executable not found at $EXECUTABLE"
    exit 1
fi

# Read version from Info.plist if not provided
PLIST_SRC="$PROJECT_DIR/Sources/$APP_NAME/Info.plist"
if [[ -z "$VERSION" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_SRC")
fi

echo "==> Bundling $APP_NAME.app (version $VERSION)..."

# Create .app bundle structure
APP_DIR="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy and patch Info.plist
cp "$PLIST_SRC" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP_DIR/Contents/Info.plist"

# Copy entitlements into Resources (informational; code signing uses them separately)
ENTITLEMENTS="$PROJECT_DIR/Sources/$APP_NAME/$APP_NAME.entitlements"
if [[ -f "$ENTITLEMENTS" ]]; then
    cp "$ENTITLEMENTS" "$APP_DIR/Contents/Resources/"
fi

# Write PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "==> Built $APP_DIR"

if [[ "$CREATE_DMG" == true ]]; then
    ARCH="arm64"
    DMG_NAME="$APP_NAME-$VERSION-$ARCH"
    DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"
    STAGING_DIR="$BUILD_DIR/dmg-staging"

    echo "==> Creating DMG ($DMG_NAME.dmg)..."

    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"
    cp -R "$APP_DIR" "$STAGING_DIR/"
    ln -s /Applications "$STAGING_DIR/Applications"

    rm -f "$DMG_PATH"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$STAGING_DIR" \
        -ov \
        -format UDZO \
        "$DMG_PATH"

    rm -rf "$STAGING_DIR"

    echo "==> Created $DMG_PATH"
fi

echo "==> Done."
