#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

./build.sh
APP_PATH="${BARAM_APP_PATH:-dist/Baram.app}"
APP_PATH="${APP_PATH:A}"
RELEASE_DIR="${BARAM_RELEASE_DIR:-dist}"
RELEASE_DIR="${RELEASE_DIR:A}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARCH="$(uname -m)"
BASE="Baram-v${VERSION}-macOS-${ARCH}"
mkdir -p "$RELEASE_DIR"
codesign --verify --deep --strict "$APP_PATH"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/baram-release.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
chmod 755 "$STAGING"
ditto --norsrc --noextattr "$APP_PATH" "$STAGING/Baram.app"
ln -s /Applications "$STAGING/Applications"
ditto --norsrc --noextattr docs/INSTALL.txt "$STAGING/설치 안내.txt"

ditto -c -k --norsrc --noextattr --keepParent "$APP_PATH" "$RELEASE_DIR/$BASE.zip"
hdiutil create -volname "Baram $VERSION" -srcfolder "$STAGING" -format UDZO -fs HFS+ -ov "$RELEASE_DIR/$BASE.dmg"
(cd "$RELEASE_DIR" && shasum -a 256 "$BASE.dmg" "$BASE.zip" > "$BASE-SHA256SUMS.txt")
echo "Release files: $RELEASE_DIR/$BASE.{dmg,zip}"
