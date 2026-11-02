#!/bin/sh
# Fails when a commit in BASE..HEAD, or the pull request description (in
# $BODY), credits an AI tool as an author or co-author. ThockBox's history
# credits people only; AI tools that help write it aren't listed as authors.
#
#   scripts/check_no_ai_credit.sh <base> <head>
set -eu
[ $# -eq 2 ] || { echo "usage: $0 <base> <head>" >&2; exit 2; }
for ref in "$1" "$2"; do
    git rev-parse --verify --quiet "$ref^{commit}" >/dev/null ||
        { echo "unknown commit: $ref" >&2; exit 2; }
done

tools='claude|anthropic|copilot|chatgpt|openai|codex|cursor|gemini|devin'
pattern="^(co-authored-by|signed-off-by):.*($tools)|generated (with|by) .*($tools)|noreply@anthropic\.com"

found=$(
    {
        git log --format='%h author: %an <%ae>%n%B' "$1..$2"
        printf '%s\n' "${BODY:-}"
    } | grep -Ei "$pattern|^[0-9a-f]+ author: .*($tools)" || true
)

if [ -n "$found" ]; then
    echo "These lines credit an AI tool. Remove them from the commits or the description:"
    echo "$found"
    exit 1
fi
echo "No AI credits in $(git rev-list --count "$1..$2") commits or the description."
