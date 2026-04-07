#!/bin/bash
set -e

APP_NAME="CodeIsland"
APP_BUNDLE=".build/release/$APP_NAME.app"

echo "Building $APP_NAME..."
bash build.sh || true

echo "Stopping running instance..."
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
sleep 1

# Force kill if still running
pkill -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

echo "Launching $APP_NAME..."
open "$APP_BUNDLE"

echo "Done."
