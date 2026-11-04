#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-app.sh

APP="build/MemoLine.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/MemoLine" | tr ' ' '-')"
DIST="dist"
ARCHIVE="MemoLine-${VERSION}-macOS-${ARCHITECTURES}.zip"

mkdir -p "$DIST"
find "$DIST" -maxdepth 1 -type f -name 'MemoLine-*-macOS-*.zip' -delete
rm -f "$DIST/SHA256SUMS.txt"
# Remove local Finder metadata before archiving. This does not remove the
# quarantine attribute that macOS applies later when a user downloads the ZIP.
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"
# The app uses ordinary bundle resources and needs no Finder resource forks.
# zip preserves executable permissions without serializing local provenance
# attributes into AppleDouble files.
(
    cd build
    /usr/bin/zip -qry "../$DIST/$ARCHIVE" MemoLine.app
)
(
    cd "$DIST"
    shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt
)

printf 'Created %s\n' "$PWD/$DIST/$ARCHIVE"
printf 'Created %s\n' "$PWD/$DIST/SHA256SUMS.txt"
