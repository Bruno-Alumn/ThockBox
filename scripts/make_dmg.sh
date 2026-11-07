#!/bin/sh
# Build the release disk image: ThockBox.app next to a link to
# Applications, so it installs by dragging one onto the other.
# Run via: make dmg
set -eu

APP=$1
DMG=$2
SIGN=${3:--}

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$APP" "$stage/$(basename "$APP")"
ln -s /Applications "$stage/Applications"

rm -f "$DMG"
hdiutil create -volname ThockBox -srcfolder "$stage" -fs HFS+ -format UDZO -ov -quiet "$DMG"
case "$SIGN" in
    -) ;;
    # Notarization needs a secure timestamp on the disk image's signature too.
    "Developer ID Application:"*) codesign --timestamp --sign "$SIGN" "$DMG" ;;
    *) codesign --sign "$SIGN" "$DMG" ;;
esac
echo "$DMG"
