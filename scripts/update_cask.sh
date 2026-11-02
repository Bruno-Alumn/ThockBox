#!/bin/sh
# Set the cask's version and sha256 from a release zip.
# Run via: make cask (after make zip).
set -eu
cask=packaging/thockbox.rb
version=$1
zip=$2
sum=$(shasum -a 256 "$zip" | cut -d' ' -f1)
sed -i '' -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sum\"/" "$cask"
echo "$cask: version $version, sha256 $sum"
