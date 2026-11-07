#!/bin/sh
# Notarize a Developer ID build with Apple and staple the ticket to it.
#
#   scripts/notarize.sh <app or dmg>
#
# An app is sent as a zip (notarytool doesn't take a bare bundle); a disk
# image is sent as is. Uses the notarytool keychain profile in
# NOTARY_PROFILE (default tuckaway-notary), which holds the Apple ID login;
# see docs/RELEASING.md.
set -eu

TARGET=$1
PROFILE=${NOTARY_PROFILE:-tuckaway-notary}

case "$TARGET" in
    *.app)
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        upload="$work/$(basename "$TARGET" .app).zip"
        ditto -c -k --keepParent "$TARGET" "$upload"
        ;;
    *) upload=$TARGET ;;
esac

result=$(xcrun notarytool submit "$upload" --keychain-profile "$PROFILE" --wait --timeout 2h) || true
echo "$result"
if ! echo "$result" | grep -q "status: Accepted"; then
    echo "error: notarization of $TARGET wasn't accepted; see 'xcrun notarytool log <id> --keychain-profile $PROFILE'" >&2
    exit 1
fi
xcrun stapler staple "$TARGET"

case "$TARGET" in
    *.app) spctl --assess --type execute -v "$TARGET" ;;
    *) spctl --assess --type open --context context:primary-signature -v "$TARGET" ;;
esac
