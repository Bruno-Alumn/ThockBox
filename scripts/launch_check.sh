#!/bin/sh
# Launch the built app as a user would, interface and all, and fail if it
# runs away: high CPU or growing memory. The unit tests and `make bench`
# don't run the app's SwiftUI scene, so a scene update loop (#23: 94% CPU,
# 1.3 GB within minutes) got past both.
#
# Run via `make test`. It launches a copy with its own bundle ID, so the
# real app's settings, stats and Accessibility grant are never touched, and
# the copy doesn't check for updates or ask for Accessibility access.
set -eu

BUNDLE=$1
ID=io.github.bruno-alumn.thockbox.healthcheck
MAX_CPU=5        # percent of one core, averaged over the measurement
MAX_RSS_MB=250   # ~85 MB today

work=$(mktemp -d)
pid=""
cleanup() {
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    defaults delete "$ID" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

cp -R "$BUNDLE" "$work/"
app="$work/$(basename "$BUNDLE")"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" "$app/Contents/Info.plist"
codesign --force --sign - "$app" 2>/dev/null
defaults write "$ID" checkForUpdates -bool false

"$app/Contents/MacOS/Thockbox" --health-check >/dev/null 2>&1 &
pid=$!

cpu_seconds() {
    # ps cputime is [[dd-]hh:]mm:ss.cc
    ps -o time= -p "$pid" | awk -F'[:-]' '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'
}

sleep 8   # launch and settle: first-launch settings window, pack decoding
kill -0 "$pid" 2>/dev/null || { echo "FAIL: app exited during launch"; exit 1; }
start=$(cpu_seconds)
rss_start=$(ps -o rss= -p "$pid")
sleep 15
end=$(cpu_seconds)
rss_end=$(ps -o rss= -p "$pid")

cpu=$(echo "$start $end" | awk '{ printf "%.1f", ($2 - $1) / 15 * 100 }')
rss=$((rss_end / 1024))
growth=$(((rss_end - rss_start) / 1024))
echo "launched app: ${cpu}% CPU, ${rss} MB memory (${growth} MB growth over 15 s)"

failed=0
awk "BEGIN { exit !($cpu > $MAX_CPU) }" && { echo "FAIL: CPU above ${MAX_CPU}%"; failed=1; }
[ "$rss" -gt "$MAX_RSS_MB" ] && { echo "FAIL: memory above ${MAX_RSS_MB} MB"; failed=1; }
[ "$growth" -gt 20 ] && { echo "FAIL: memory still growing"; failed=1; }
[ "$failed" -eq 0 ] && echo "OK"
exit "$failed"
