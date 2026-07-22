#!/bin/bash
# Assembles the universal, self-contained "fi-6110 Scanner.app" into dist/.
#   - universal release build of the SwiftUI app (arm64 + x86_64, macOS 12+)
#   - bundled SANE fujitsu backend + libusb in Contents/Frameworks
#   - fujitsu.conf in Contents/Resources/sane.d
#   - ad-hoc code signature (no developer account needed)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$DIR")"
APP_NAME="fi-6110 Scanner"
DIST="$REPO/dist"
APP="$DIST/$APP_NAME.app"

CODESIGN=/usr/bin/codesign
LIPO=/usr/bin/lipo

if [[ ! -f "$REPO/vendor/out/lib/libsane-fujitsu.so" ]]; then
    echo ">>> vendor libraries missing — building them first"
    "$REPO/vendor/build-sane.sh"
fi

if [[ ! -f "$DIR/AppIcon.icns" ]]; then
    echo ">>> icon missing — rendering it"
    "$DIR/make-icon.sh"
fi

echo ">>> building universal release binary"
cd "$REPO"
swift build -c release --arch arm64 --arch x86_64

PRODUCTS="$REPO/.build/apple/Products/Release"
BINARY="$PRODUCTS/FiScanner"
RESOURCE_BUNDLE="$PRODUCTS/FiScanner_FiScanner.bundle"

"$LIPO" -info "$BINARY" | grep -q "x86_64 arm64\|arm64 x86_64" || {
    echo "ERROR: FiScanner binary is not universal" >&2
    exit 1
}

echo ">>> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/sane.d"

cp "$DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$BINARY" "$APP/Contents/MacOS/FiScanner"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
cp "$DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$REPO/vendor/out/lib/libsane-fujitsu.so" "$APP/Contents/Frameworks/"
cp "$REPO/vendor/out/lib/libusb-1.0.0.dylib" "$APP/Contents/Frameworks/"
cp "$REPO/vendor/out/etc/sane.d/fujitsu.conf" "$APP/Contents/Resources/sane.d/"

echo ">>> ad-hoc signing"
"$CODESIGN" --force -s - "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
"$CODESIGN" --force -s - "$APP/Contents/Frameworks/libsane-fujitsu.so"
"$CODESIGN" --force -s - --identifier com.federicomarra.fi6110-scanner "$APP"

echo ">>> verifying"
"$CODESIGN" --verify --strict --deep "$APP"
"$LIPO" -info "$APP/Contents/MacOS/FiScanner"
otool -l "$APP/Contents/MacOS/FiScanner" | awk '/LC_BUILD_VERSION/{v=1} v&&/minos/{print "minos:", $2; v=0}' | head -2
echo ">>> OK: $APP"
