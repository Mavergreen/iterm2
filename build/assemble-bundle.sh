#!/bin/sh
# platform: macOS-only -- makes the icon with iconutil and edits Info.plist with plutil (both on 10.9).
#   usage: assemble-bundle.sh OUT_APP SOURCE_DIR COMPILED_DIR APP_EXE IMAGE_DECODER COLORPICKER_FRAMEWORK VERSION RESTART_HELPER
#          Assembles iTerm2.app at OUT_APP (which must not exist) from explicit inputs only:
#            - APP_EXE as Contents/MacOS/iTerm2, RESTART_HELPER as Contents/MacOS/restart-for-update (the
#              family updater's post-update helper), and IMAGE_DECODER as Contents/Resources/image_decoder
#              (0755), beside upstream's OtherResources/image_decoder.sb;
#            - each resources/compiled.tsv destination from COMPILED_DIR (B3's verified extraction of the
#              release's nibs and model), and each resources/app-resources.tsv file from SOURCE_DIR;
#            - Contents/Resources/iTerm2.icns, made by iconutil from Media.xcassets/AppIcon.appiconset;
#              a catalog holding anything else is refused, never dropped (no actool here);
#            - COLORPICKER_FRAMEWORK (the rebuilt one) as Contents/Frameworks/ColorPicker.framework;
#            - Info.plist: upstream's plists/iTerm2.plist with the Mavergreen identity, VERSION
#              (<upstream>-mavericks.N) and its comparison key, the 10.9 floor, and no SU* key; PkgInfo.
#          It is built beside OUT_APP, checked with build/check-bundle.sh, and only then renamed into place.
# spec: BUILD.md "Resources and the bundle".
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
[ "$#" -eq 8 ] || { echo 'usage: assemble-bundle.sh OUT_APP SOURCE_DIR COMPILED_DIR APP_EXE IMAGE_DECODER COLORPICKER_FRAMEWORK VERSION RESTART_HELPER' >&2; exit 2; }
OUT=$1; SRC=$2; COMPILED=$3; EXE=$4; DECODER=$5; FW=$6; VERSION=$7; HELPER=$8
die() { echo "assemble-bundle: $*" >&2; exit 1; }
[ ! -e "$OUT" ] && [ ! -L "$OUT" ] || die "$OUT already exists"
printf '%s\n' "$VERSION" | grep -Eqx '[0-9]+(\.[0-9]+)*-mavericks\.[1-9][0-9]*' || die "VERSION '$VERSION' is not <upstream>-mavericks.N"
TAB=$(printf '\t')
. "$REPO_ROOT/build/msc.sh"
. "$SHIPYARD_SCRIPTS/lib/vercmp.sh"
key=$(comparison_key "$VERSION") || die "no comparison key for $VERSION"

mkdir -p "$(dirname "$OUT")"
tmp=$(mktemp -d "$(dirname "$OUT")/.assemble.XXXXXX")   # platform: 10.9 BSD mktemp requires a template
trap 'rm -rf "$tmp"' EXIT
A="$tmp/iTerm2.app/Contents"
mkdir -p "$A/MacOS" "$A/Resources/Model.momd" "$A/Frameworks"
cp "$EXE" "$A/MacOS/iTerm2" && chmod 755 "$A/MacOS/iTerm2"
cp "$HELPER" "$A/MacOS/restart-for-update" && chmod 755 "$A/MacOS/restart-for-update"
cp "$DECODER" "$A/Resources/image_decoder" && chmod 755 "$A/Resources/image_decoder"
cp "$SRC/OtherResources/image_decoder.sb" "$A/Resources/image_decoder.sb"
tail -n +2 "$REPO_ROOT/resources/compiled.tsv" | while IFS="$TAB" read -r member dest kind bytes sha; do
  mkdir -p "$(dirname "$A/Resources/$dest")"
  cp "$COMPILED/$dest" "$A/Resources/$dest" || exit 1
done || die "a compiled resource is missing from $COMPILED"
tail -n +2 "$REPO_ROOT/resources/app-resources.tsv" | while IFS="$TAB" read -r s d; do
  cp "$SRC/$s" "$A/Resources/$d" || exit 1
done || die "a listed source resource is missing from $SRC"
sh "$REPO_ROOT/build/make-icns.sh" "$SRC" "$A/Resources/iTerm2.icns" || die "no iTerm2.icns"
# spec: BUILD.md "Resources and the bundle" -- the compiled MainMenu nib names the asset-catalog image
#       AppIcon, which this bundle carries as AppIcon.icns, upstream's own icon again
cp "$A/Resources/iTerm2.icns" "$A/Resources/AppIcon.icns"
cp -R "$FW" "$A/Frameworks/ColorPicker.framework"
chmod -R u+w,go-w "$A"
find "$A/Resources" -type f ! -name image_decoder -exec chmod 644 {} +

plist="$A/Info.plist"
plutil -convert xml1 -o "$plist" "$SRC/plists/iTerm2.plist"
for k in SUFeedURLForFinal SUFeedURLForTesting SUPublicDSAKeyFile; do plutil -remove "$k" "$plist" 2>/dev/null || :; done
plutil -replace CFBundleIdentifier -string dev.mavergreen.iterm2.app "$plist"
plutil -replace CFBundleName -string "Mavericks iTerm2" "$plist"
plutil -replace CFBundleDisplayName -string "Mavericks iTerm2" "$plist"
plutil -replace CFBundleExecutable -string iTerm2 "$plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$plist"
plutil -replace CFBundleVersion -string "$key" "$plist"
plutil -replace CFBundleGetInfoString -string "Mavericks iTerm2 $VERSION" "$plist"
plutil -replace LSMinimumSystemVersion -string 10.9 "$plist"
printf 'APPLITRM' > "$A/PkgInfo"

sh "$REPO_ROOT/build/check-bundle.sh" "$tmp/iTerm2.app" "$SRC" >&2 || die "the assembled bundle failed check-bundle.sh"
mv "$tmp/iTerm2.app" "$OUT"
echo "$OUT"
