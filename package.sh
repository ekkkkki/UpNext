#!/bin/bash
# Builds QuickAdd, assembles a signed .app bundle, and produces a distributable DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="QuickAdd"
BUILD_DIR="$ROOT/.build/release"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

mkdir -p "$DIST"

echo "==> Building release binary"
swift build -c release --product "$APP_NAME"

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Generating app icon"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
if swift "$ROOT/Packaging/make_icon.swift" "$ICONSET" >/dev/null 2>&1 \
   && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    echo "    icon embedded"
else
    echo "    (icon generation skipped — app still works without a custom icon)"
fi
rm -rf "$ICONSET"

echo "==> Code signing (ad-hoc)"
codesign --force --entitlements "$ROOT/Packaging/QuickAdd.entitlements" --sign - "$APP"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /' || true

echo "==> Creating DMG"
DMG="$DIST/$APP_NAME.dmg"
rm -f "$DMG"
STAGING="$DIST/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo ""
echo "==> Done"
echo "    App: $APP"
echo "    DMG: $DMG"
echo ""
echo "Install: drag QuickAdd.app to /Applications, then launch it."
echo "First launch will ask for Reminders & Calendar access. Press ⇧⌘A to capture."
