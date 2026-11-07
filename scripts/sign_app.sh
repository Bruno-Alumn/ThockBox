#!/bin/sh
# Sign ThockBox.app for release, or ad-hoc for a local build.
#
#   scripts/sign_app.sh <app> <identity>
#
# Every release carries the designated requirement in
# packaging/designated_requirement.txt, which accepts both the old
# "ThockBox Signing" certificate and the maintainer's Developer ID. macOS
# keeps the Accessibility and other grants for any build that meets the
# running app's requirement, and the updater only installs such builds, so
# this one requirement is what lets releases move between the two
# identities without anyone losing a permission. See docs/RELEASING.md.
#
# Developer ID builds also get a secure timestamp, which notarization needs.
# All builds use the hardened runtime with packaging/ThockBox.entitlements.
set -eu

APP=$1
IDENTITY=$2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENTITLEMENTS="$ROOT/packaging/ThockBox.entitlements"
REQUIREMENT=$(cat "$ROOT/packaging/designated_requirement.txt")

if [ "$IDENTITY" = "-" ]; then
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP"
    exit 0
fi

case "$IDENTITY" in
    "Developer ID Application:"*) TIMESTAMP=--timestamp ;;
    *) TIMESTAMP= ;;
esac

# The app has no nested code (frameworks, helpers or plug-ins); if it ever
# does, sign those first, from the inside out.
codesign --force --options runtime --entitlements "$ENTITLEMENTS" $TIMESTAMP \
    -r="designated => $REQUIREMENT" --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
if ! codesign --verify -R="$REQUIREMENT" "$APP"; then
    echo "error: $APP doesn't meet packaging/designated_requirement.txt" >&2
    exit 1
fi
