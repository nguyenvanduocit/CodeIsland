#!/bin/bash
set -e

APP_NAME="CodeIsland"
BUILD_DIR=".build/debug"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Helpers"
mkdir -p "$APP_BUNDLE/Contents/Resources"

ARCH_DIR=".build/debug"
cp "$ARCH_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ARCH_DIR/codeisland-bridge" "$APP_BUNDLE/Contents/Helpers/codeisland-bridge"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Copy SPM resource bundles
for bundle in .build/*/debug/*.bundle; do
    if [ -e "$bundle" ]; then
        cp -R "$bundle" "$APP_BUNDLE/"
        break
    fi
done

echo "Stopping running instance..."
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
sleep 1
killall -9 "$APP_NAME" 2>/dev/null || true
sleep 1

echo "Launching $APP_NAME..."
open "$APP_BUNDLE"

echo "Done."
