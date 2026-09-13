#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
BUILD_ROOT="${BARAM_BUILD_ROOT:-.build}"
BUILD_ROOT="${BUILD_ROOT:A}"
mkdir -p "$BUILD_ROOT/module-cache"
swift build -c release --scratch-path "$BUILD_ROOT" -Xswiftc -module-cache-path -Xswiftc "$BUILD_ROOT/module-cache"
BIN_DIR="$(swift build -c release --scratch-path "$BUILD_ROOT" --show-bin-path)"
APP_PATH="${BARAM_APP_PATH:-dist/Baram.app}"
APP_PATH="${APP_PATH:A}"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/Baram" "$APP_PATH/Contents/MacOS/Baram"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/"
fi
codesign --force --deep --sign - "$APP_PATH"
echo "Built: ${APP_PATH:A}"
