#!/bin/bash
# Builds dist/fi-6110 Scanner.dmg: the app, an Applications shortcut for
# drag-installing, and Italian first-launch instructions (Leggimi.rtf).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$DIR")"
APP_NAME="fi-6110 Scanner"
DIST="$REPO/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"
VOLNAME="fi-6110 Scanner"

if [[ ! -d "$APP" ]]; then
    echo ">>> app missing — building it first"
    "$DIR/make-app.sh"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo ">>> staging DMG contents"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applicazioni"
textutil -convert rtf -output "$STAGE/Leggimi.rtf" "$DIR/Leggimi.html"

echo ">>> creating DMG"
rm -f "$DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"

echo ">>> verifying DMG mounts"
MOUNT="$(hdiutil attach "$DMG" -readonly -nobrowse | awk -F'\t' '/Volumes/{print $NF}')"
ls "$MOUNT"
hdiutil detach "$MOUNT" -quiet

echo ">>> OK: $DMG"
du -h "$DMG" | cut -f1
