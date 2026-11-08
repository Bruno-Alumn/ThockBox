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
# Only a Developer ID signs the disk image (with the secure timestamp that
# notarization needs). Gatekeeper doesn't trust the self-signed "ThockBox
# Signing" certificate, and a disk image signed with it gets checked and
# blocked on open, an extra "Open Anyway" that an unsigned one doesn't need.
case "$SIGN" in
    "Developer ID Application:"*) codesign --timestamp --sign "$SIGN" "$DMG" ;;
esac
echo "$DMG"
