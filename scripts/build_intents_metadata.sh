#!/bin/sh
# Generate the App Intents metadata (Metadata.appintents) that Shortcuts,
# Siri and Spotlight read, and put it in the app bundle. This is the
# "Extract App Intents Metadata" step Xcode runs; SwiftPM builds don't, but
# they do write the Swift constant values the tool needs.
#
# Run via `make bundle`. Needs Xcode (not just the Command Line Tools);
# without it the app still builds, it just won't show up in Shortcuts.
set -eu

BUNDLE=$1
MODULE=Thockbox

if ! tool=$(xcrun --find appintentsmetadataprocessor 2>/dev/null); then
    echo "note: Xcode not found; skipping Shortcuts metadata"
    exit 0
fi

consts=$(find .build -path "*/Release/$MODULE-p.build/*" -name "$MODULE-primary.swiftconstvalues" | head -1)
sources=$(find .build -path "*/Release/$MODULE-p.build/*" -name "$MODULE.SwiftFileList" | head -1)
if [ -z "$consts" ] || [ -z "$sources" ]; then
    # Older SwiftPM build systems don't write constant values.
    echo "warning: no Swift constant values for $MODULE; skipping Shortcuts metadata" >&2
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "$(pwd)/$consts" > "$work/consts.list"

"$tool" \
    --output "$BUNDLE/Contents/Resources" \
    --toolchain-dir "$(dirname "$(dirname "$(dirname "$tool")")")" \
    --module-name "$MODULE" \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" \
    --platform-family macOS \
    --deployment-target 13.0 \
    --target-triple "$(uname -m)-apple-macos13.0" \
    --source-file-list "$sources" \
    --swift-const-vals-list "$work/consts.list" \
    --no-app-shortcuts-localization \
    --force

echo "$BUNDLE: Shortcuts metadata ($(ls "$BUNDLE/Contents/Resources/Metadata.appintents" | tr '\n' ' '))"
