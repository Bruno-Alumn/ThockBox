#!/bin/sh
# Prints CHANGELOG.md's section for a version, for the GitHub release's
# notes: the same words people see in What's New, which the in-app updater
# previews in Settings before installing.
# Usage: scripts/release_notes.sh 1.11.1
set -eu
version="$1"
notes=$(awk -v heading="## $version" '
    $0 == heading { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
' CHANGELOG.md | sed -e '/./,$!d')
if [ -z "$notes" ]; then
    echo "CHANGELOG.md has no \"## $version\" section" >&2
    exit 1
fi
printf '%s\n' "$notes"
