#!/bin/sh
# platform: macOS-only -- iconutil writes the .icns
#   usage: make-icns.sh SOURCE_DIR OUT_ICNS
#          Makes OUT_ICNS from the prepared source's Media.xcassets/AppIcon.appiconset, upstream's app icon,
#          refusing a catalog that holds anything else or lacks one of the ten iconset sizes.
set -eu
[ "$#" -eq 2 ] || { echo 'usage: make-icns.sh SOURCE_DIR OUT_ICNS' >&2; exit 2; }
SRC=$1; OUT=$2
die() { echo "make-icns: $*" >&2; exit 1; }
cat="$SRC/Media.xcassets"
[ "$(ls "$cat" | tr '\n' ' ')" = "AppIcon.appiconset Contents.json " ] \
  || die "the asset catalog holds more than AppIcon ($(ls "$cat" | tr '\n' ' ')); this build makes only the app icon"
icons='Contents.json icon_128x128.png icon_128x128@2x.png icon_16x16.png icon_16x16@2x.png icon_256x256.png icon_256x256@2x.png icon_32x32.png icon_32x32@2x.png icon_512x512.png icon_512x512@2x.png '
[ "$(ls "$cat/AppIcon.appiconset" | tr '\n' ' ')" = "$icons" ] \
  || die "AppIcon.appiconset is not the ten iconset sizes: $(ls "$cat/AppIcon.appiconset" | tr '\n' ' ')"
mkdir -p "$(dirname "$OUT")"
tmp=$(mktemp -d "$(dirname "$OUT")/.icns.XXXXXX")   # platform: 10.9 BSD mktemp requires a template
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/iTerm2.iconset"
cp "$cat/AppIcon.appiconset/"icon_*.png "$tmp/iTerm2.iconset/"
iconutil -c icns -o "$OUT" "$tmp/iTerm2.iconset" || die "iconutil could not make $OUT"
