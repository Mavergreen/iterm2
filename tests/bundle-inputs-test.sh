#!/bin/sh
# platform: macOS-only -- assembles with iconutil and plutil, and builds stand-in Mach-O files with clang22.
# spec: BUILD.md "Resources and the bundle" -- the app is assembled only from explicit inputs: exactly the 31 compiled resources the
#       release manifest measured, the listed source resources, rebuilt code and the rebuilt ColorPicker;
#       build/check-bundle.sh refuses a bundle with a missing or stale nib, a missing model, a misplaced
#       or non-executable image_decoder, no sandbox profile, a bad Info.plist, an extra executable, any
#       Growl/NMSSH/Sparkle trace, or the prebuilt ColorPicker; an asset catalog with more than AppIcon
#       is refused rather than dropped.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-bundle-test.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
T=$(CDPATH= cd "$T" && pwd -P)
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
. "$REPO_ROOT/build/msc.sh"
R="$REPO_ROOT/resources"

[ "$(head -1 "$R/compiled.tsv")" = "$(printf 'member\tdestination\tkind\tbytes\tsha256')" ] || fail "compiled.tsv header"
[ "$(tail -n +2 "$R/compiled.tsv" | wc -l | tr -d ' ')" = 31 ] || fail "compiled.tsv does not list 31 members"
[ "$(tail -n +2 "$R/compiled.tsv" | grep -c '\.nib	')" = 29 ] || fail "compiled.tsv does not list 29 nibs"
tail -n +2 "$R/compiled.tsv" | grep -q '^Model\.momd/Model\.mom	Model\.momd/Model\.mom	file	' || fail "no Model.mom"
tail -n +2 "$R/compiled.tsv" | grep -q '^Model\.momd/VersionInfo\.plist	' || fail "no model VersionInfo.plist"
tail -n +2 "$R/compiled.tsv" | awk -F'\t' '$1 != $2 || $3 != "file" || $5 !~ /^[0-9a-f]{64}$/' | grep -q . \
  && fail "a compiled.tsv row is not member=destination, kind file, a SHA-256"
tail -n +2 "$R/compiled.tsv" | cut -f1 | grep -E '^(\.\.|/)|MacOS|Frameworks|Sparkle|Growl|NMSSH|\.app/|\.framework/' \
  && fail "compiled.tsv selects a member outside the app's own resources"
grep -q 'ColorPicker\|Demo\|\.xib	' "$R/app-resources.tsv" && fail "app-resources.tsv lists a ColorPicker, demo or XIB input"
grep -qi 'growl\|sparkle\|dsa_pub' "$R/app-resources.tsv" && fail "app-resources.tsv lists an updater or Growl resource"

v() { sed -n "s/^$2=//p" "$REPO_ROOT/components/$1/version"; }
sh "$SHIPYARD_SCRIPTS/fetch_pinned_source.sh" "$(v iterm2 REPO)" "$(v iterm2 DIGEST)" "$(v iterm2 SHA256)" "$T/src" 2>/dev/null \
  || { echo "bundle-inputs-test: the pinned source did not fetch" >&2; exit 1; }
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"
CACHE=${MAVERICKS_SOURCE_CACHE:-$HOME/Library/Caches/mavericks-sources}; mkdir -p "$CACHE"
zip="iTerm2-resources-$(v iterm2-resources VERSION)-$(v iterm2-resources SHA256).zip"
shipyard_fetch_verified "$(v iterm2-resources URL)" "$(v iterm2-resources SHA256)" "$CACHE" "$zip" 2>/dev/null \
  || { echo "bundle-inputs-test: the resource ZIP did not fetch" >&2; exit 1; }
mkdir -p "$T/zip" "$T/compiled"
(cd "$T/zip" && unzip -q "$CACHE/$zip" 'iTerm.app/Contents/Resources/*.nib' 'iTerm.app/Contents/Resources/Model.momd/*')
cp -R "$T/zip/iTerm.app/Contents/Resources/." "$T/compiled/"
for c in /usr/local/mavergreen/clang22/bin/clang /usr/local/mavergreen/clang22-cross/bin/clang; do
  [ -x "$c" ] && CLANG22=$c && break
done
[ -n "${CLANG22:-}" ] || { echo "bundle-inputs-test: no clang22" >&2; exit 1; }
printf 'int main(void) { return 0; }\n' > "$T/main.c"
"$CLANG22" -o "$T/iTerm2" "$T/main.c"
"$CLANG22" -o "$T/image_decoder" "$T/main.c"
"$CLANG22" -o "$T/restart-for-update" "$T/main.c"
mkdir -p "$T/fw/ColorPicker.framework/Versions/A/Resources"
printf 'int cpk(void) { return 1; }\n' > "$T/cpk.c"
"$CLANG22" -dynamiclib -install_name @rpath/ColorPicker.framework/Versions/A/ColorPicker \
  -o "$T/fw/ColorPicker.framework/Versions/A/ColorPicker" "$T/cpk.c"
(cd "$T/fw/ColorPicker.framework" && ln -s A Versions/Current && ln -s Versions/Current/ColorPicker ColorPicker \
  && ln -s Versions/Current/Resources Resources)

assemble() { # OUT -- assemble a bundle from the inputs above
  sh "$REPO_ROOT/build/assemble-bundle.sh" "$1" "$T/src" "$T/compiled" "$T/iTerm2" "$T/image_decoder" \
    "$T/fw/ColorPicker.framework" 3.0.15-mavericks.1 "$T/restart-for-update" >"$T/log" 2>&1
}
check() { sh "$REPO_ROOT/build/check-bundle.sh" "$1" "$T/src" >"$T/log" 2>&1; }
logged() { tr '\n' ' ' < "$T/log" | tr -s ' ' | grep -q -- "$1"; }

if assemble "$T/good/iTerm2.app"; then
  A="$T/good/iTerm2.app/Contents"
  check "$T/good/iTerm2.app" || { cat "$T/log" >&2; fail "check-bundle refused the assembled bundle"; }
  [ "$(cd "$A/Resources" && ls *.nib | wc -l | tr -d ' ')" = 29 ] || fail "the bundle does not hold 29 nibs"
  [ -f "$A/Resources/Model.momd/Model.mom" ] || fail "no Model.mom in the bundle"
  [ -f "$A/Resources/iTerm2.icns" ] || fail "no iTerm2.icns"
  [ "$(ls -l "$A/Resources/image_decoder" | cut -c1-10)" = -rwxr-xr-x ] || fail "image_decoder is not 0755"
  [ -f "$A/Resources/image_decoder.sb" ] || fail "no image_decoder.sb"
  [ ! -e "$A/MacOS/image_decoder" ] || fail "image_decoder is in MacOS"
  [ "$(ls "$A/Frameworks")" = ColorPicker.framework ] || fail "Frameworks is not exactly ColorPicker.framework"
  [ "$(ls "$A/MacOS" | tr '\n' ' ')" = 'iTerm2 restart-for-update ' ] || fail "MacOS is not exactly iTerm2 and restart-for-update"
  [ "$(ls -l "$A/MacOS/restart-for-update" | cut -c1-10)" = -rwxr-xr-x ] || fail "restart-for-update is not 0755"
  p() { plutil -extract "$1" xml1 -o - "$A/Info.plist" 2>/dev/null | sed -n 's:.*<string>\(.*\)</string>.*:\1:p'; }
  [ "$(p CFBundleIdentifier)" = dev.mavergreen.iterm2.app ] || fail "CFBundleIdentifier"
  [ "$(p CFBundleDisplayName)" = "Mavericks iTerm2" ] || fail "CFBundleDisplayName"
  [ "$(p CFBundleExecutable)" = iTerm2 ] || fail "CFBundleExecutable"
  [ "$(p CFBundleShortVersionString)" = 3.0.15-mavericks.1 ] || fail "CFBundleShortVersionString"
  [ "$(p CFBundleVersion)" = 3.0.15.1 ] || fail "CFBundleVersion is not the comparison key"
  [ "$(p LSMinimumSystemVersion)" = 10.9 ] || fail "LSMinimumSystemVersion"
  [ "$(p NSMainNibFile)" = MainMenu ] && [ "$(p NSPrincipalClass)" = iTermApplication ] \
    && [ "$(p OSAScriptingDefinition)" = iTerm2.sdef ] || fail "an upstream Info.plist field was lost"
  plutil -convert xml1 -o - "$A/Info.plist" | grep -q '<key>SU' && fail "an SU* key is in Info.plist"
  [ "$(cat "$A/PkgInfo")" = APPLITRM ] || fail "PkgInfo"
  [ "$(sed -n '$=' "$R/app-resources.tsv")" -gt 1 ] && tail -n +2 "$R/app-resources.tsv" | while IFS="$(printf '\t')" read -r s d; do
    cmp -s "$T/src/$s" "$A/Resources/$d" || { echo "x"; break; }
  done | grep -q x && fail "a listed source resource is missing or differs"
  ls "$A/Resources" | grep -qiE '\.xib$|dsa_pub|growl|xcassets' && fail "a source-only or dropped resource was copied"

  bad() { # NAME MUTATION... -- copy the good bundle, mutate it, and expect check-bundle to refuse it
    name=$1; shift
    rm -rf "$T/bad"; mkdir -p "$T/bad"; cp -R "$T/good/iTerm2.app" "$T/bad/iTerm2.app"
    B="$T/bad/iTerm2.app/Contents"
    eval "$*"
    if check "$T/bad/iTerm2.app"; then fail "check-bundle accepted: $name"; else echo "  refused $name: $(grep -v refused "$T/log" | head -1 | cut -c1-150)"; fi
    unset OTOOL
  }
  bad missing-nib 'rm "$B/Resources/MainMenu.nib"'
  bad stale-nib 'printf x >> "$B/Resources/AboutWindow.nib"'
  bad missing-model 'rm "$B/Resources/Model.momd/Model.mom"'
  bad missing-model-version 'rm "$B/Resources/Model.momd/VersionInfo.plist"'
  bad decoder-mode 'chmod 644 "$B/Resources/image_decoder"'
  bad missing-restart-helper 'rm "$B/MacOS/restart-for-update"'
  bad decoder-in-macos 'mv "$B/Resources/image_decoder" "$B/MacOS/image_decoder"'
  bad no-sandbox 'rm "$B/Resources/image_decoder.sb"'
  bad no-icon 'rm "$B/Resources/iTerm2.icns"'
  bad wrong-bundle-id 'plutil -replace CFBundleIdentifier -string com.googlecode.iterm2 "$B/Info.plist"'
  bad sparkle-key 'plutil -insert SUFeedURL -string https://example.invalid "$B/Info.plist"'
  bad no-floor 'plutil -remove LSMinimumSystemVersion "$B/Info.plist"'
  bad extra-executable 'cp "$T/iTerm2" "$B/Resources/helper"'
  bad growl-framework 'mkdir -p "$B/Frameworks/Growl.framework"'
  bad sparkle-framework 'mkdir -p "$B/Frameworks/Sparkle.framework"'
  bad prebuilt-colorpicker 'cp "$T/src/ColorPicker/ColorPicker.framework/Versions/A/ColorPicker" "$B/Frameworks/ColorPicker.framework/Versions/A/ColorPicker"'
  bad growl-ticket 'touch "$B/Resources/Growl Registration Ticket.growlRegDict"'
  mkdir -p "$T/g"; "$CLANG22" -dynamiclib -install_name @executable_path/../Frameworks/Growl.framework/Versions/A/Growl -o "$T/g/libGrowl.dylib" "$T/cpk.c"
  printf 'int cpk(void);\nint main(void) { return cpk(); }\n' > "$T/usecpk.c"
  bad links-growl '"$CLANG22" -o "$B/MacOS/iTerm2" "$T/usecpk.c" "$T/g/libGrowl.dylib"'
  bad otool-fails 'export OTOOL=/usr/bin/false'
  printf 'extern int NMSSHSessionConnect(void);\nint main(void) { return NMSSHSessionConnect(); }\n' > "$T/usenmssh.c"
  bad references-nmssh '"$CLANG22" -o "$B/MacOS/iTerm2" "$T/usenmssh.c" -Wl,-U,_NMSSHSessionConnect'
  bad absolute-rpath '"$CLANG22" -o "$B/MacOS/iTerm2" "$T/main.c" -Wl,-rpath,@executable_path/../Frameworks -Wl,-rpath,/private/tmp/mm-build/iterm2'
else
  cat "$T/log" >&2; fail "assemble-bundle.sh failed on the pinned inputs"
fi

grep -o '"xib": "[^"]*", "xib_sha256": "[0-9a-f]*", "nib": "[^"]*", "nib_sha256": "[0-9a-f]*"' "$R/source-contract.json" \
  | sed 's/"xib": "\([^"]*\)", "xib_sha256": "\([0-9a-f]*\)", "nib": "\([^"]*\)", "nib_sha256": "\([0-9a-f]*\)"/\1|\2|\3|\4/' \
  > "$T/pairs"
[ "$(wc -l < "$T/pairs" | tr -d ' ')" = 28 ] || fail "source-contract.json does not pair 28 XIBs"
while IFS='|' read -r x xs n ns; do
  [ "$(shasum -a 256 "$T/src/$x" | cut -d' ' -f1)" = "$xs" ] || echo "contract: $x is not at its recorded SHA-256"
  [ "$(awk -F'\t' -v n="$n" '$1 == n { print $5 }' "$R/compiled.tsv")" = "$ns" ] || echo "contract: $n differs from compiled.tsv"
done < "$T/pairs" > "$T/contract"
[ ! -s "$T/contract" ] || { cat "$T/contract" >&2; fail "source-contract.json disagrees with the source or compiled.tsv"; }
grep -q '"unproven"' "$R/source-contract.json" || fail "source-contract.json does not state what is unproven"

cp -R "$T/src" "$T/src2"
mkdir -p "$T/src2/Media.xcassets/Extra.imageset"; echo '{}' > "$T/src2/Media.xcassets/Extra.imageset/Contents.json"
if sh "$REPO_ROOT/build/assemble-bundle.sh" "$T/catalog/iTerm2.app" "$T/src2" "$T/compiled" "$T/iTerm2" \
     "$T/image_decoder" "$T/fw/ColorPicker.framework" 3.0.15-mavericks.1 "$T/restart-for-update" >"$T/log" 2>&1; then
  fail "an asset catalog with Extra.imageset was accepted"
fi
logged 'Extra.imageset' || fail "the catalog refusal does not name Extra.imageset"
[ ! -e "$T/catalog/iTerm2.app" ] || fail "a refused assembly left a bundle behind"

[ "$fails" -eq 0 ] || { echo "bundle-inputs-test: $fails failure(s)" >&2; exit 1; }
echo "bundle-inputs-test: OK"
