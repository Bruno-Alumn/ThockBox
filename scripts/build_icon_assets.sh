#!/bin/sh
# Compile the layered Liquid Glass app icon (Resources/AppIcon.icon, made
# with Icon Composer) into Assets.car in the app bundle. macOS 26 and later
# show it, found through CFBundleIconName; macOS 13 to 15 keep showing
# AppIcon.icns (CFBundleIconFile), which `make icon` builds.
#
# Run via `make bundle`. Needs Xcode 26 or later, which is the first actool
# that reads .icon files. When the selected Xcode is older, the newest
# Xcode 26+ in /Applications is used for this step only. Without one the
# app still builds with just AppIcon.icns, unless REQUIRE_GLASS_ICON=1
# (as in CI), which makes that an error.
set -eu

BUNDLE=$1
ICON=Resources/AppIcon.icon

xcode_major() {
    DEVELOPER_DIR=$1 xcodebuild -version 2>/dev/null | awk 'NR == 1 { split($2, v, "."); print v[1] }'
}

developer_dir=
if dir=$(xcode-select -p 2>/dev/null) && [ "$(xcode_major "$dir")" -ge 26 ] 2>/dev/null; then
    developer_dir=$dir
else
    for app in $(ls -d /Applications/Xcode*.app 2>/dev/null | sort -rV); do
        if [ "$(xcode_major "$app/Contents/Developer")" -ge 26 ] 2>/dev/null; then
            developer_dir=$app/Contents/Developer
            break
        fi
    done
fi

if [ -z "$developer_dir" ]; then
    if [ "${REQUIRE_GLASS_ICON:-0}" = 1 ]; then
        echo "error: no Xcode 26 or later to compile $ICON" >&2
        exit 1
    fi
    echo "note: no Xcode 26 or later; skipping the Liquid Glass icon (AppIcon.icns only)"
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# actool also writes an AppIcon.icns rendered from the .icon for older
# systems. Only Assets.car is kept: the bundle's AppIcon.icns stays the one
# drawn for macOS 13 to 15.
DEVELOPER_DIR=$developer_dir xcrun actool "$ICON" \
    --compile "$work" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$work/partial.plist" \
    --output-format human-readable-text \
    --errors --warnings --notices

cp "$work/Assets.car" "$BUNDLE/Contents/Resources/"
echo "$BUNDLE: Liquid Glass icon in Assets.car ($(DEVELOPER_DIR=$developer_dir xcodebuild -version | head -1))"
