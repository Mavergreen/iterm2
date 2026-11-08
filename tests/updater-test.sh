#!/bin/sh
# platform: macOS-only -- reads the native build's bundles with clang22's llvm-otool and the system's plutil
# spec: BUILD.md "Updates" -- the family updater is built beside the app, with the identity shipyard's
#       registry derives for iterm2, upstream's icon, and nothing of the app linked into it; the app's
#       nib finds the icon it names as AppIcon.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
. "$REPO_ROOT/build/msc.sh"
B=${ITERM_BUILD_DIR:-${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/$(basename "$REPO_ROOT")-native}
APP=$B/iTerm2.app
UPD=$B/iterm2-updater.app
[ -d "$APP" ] || { echo "updater-test: no native build at $B; skipping"; exit 77; }
key() { plutil -extract "$2" xml1 -o - "$1/Contents/Info.plist" 2>/dev/null | sed -n 's|.*<string>\(.*\)</string>.*|\1|p'; }
reg() { sh "$SHIPYARD_SCRIPTS/product-name.sh" "$1" iterm2; }

[ -d "$UPD" ] || fail "no updater at $UPD"
[ "$(key "$UPD" CFBundleIdentifier)" = "$(reg updater-bundle-id)" ] || fail "the updater's bundle id is not the registry's"
[ "$(key "$UPD" SUFeedURL)" = "$(reg feed)" ] || fail "the updater's feed is not the registry's"
[ "$(key "$UPD" CFBundleName)" = "Mavericks iTerm2" ] || fail "the updater's name is not Mavericks iTerm2"
[ "$(key "$UPD" CFBundleShortVersionString)" = "$(key "$APP" CFBundleShortVersionString)" ] \
  || fail "the updater's version is not the app's"
exe=$UPD/Contents/MacOS/$(key "$UPD" CFBundleExecutable)
if [ -z "${OTOOL:-}" ]; then
  for d in /usr/local/mavergreen/clang22/bin /usr/local/mavergreen/clang22-cross/bin; do
    [ -x "$d/llvm-otool" ] && OTOOL=$d/llvm-otool && break
  done
fi
[ -n "${OTOOL:-}" ] || { echo "updater-test: no clang22 llvm-otool; set OTOOL" >&2; exit 1; }
if "$OTOOL" -L "$exe" > "${TMPDIR:-/tmp}/updater-test.$$" 2>&1; then
  ! tail -n +2 "${TMPDIR:-/tmp}/updater-test.$$" | grep -qi 'iterm' || fail "the updater links something of iTerm2's"
else
  fail "$OTOOL could not read $exe"
fi
rm -f "${TMPDIR:-/tmp}/updater-test.$$"
icon=$UPD/Contents/Resources/$(key "$UPD" CFBundleIconFile)
case "$icon" in *.icns) ;; *) icon=$icon.icns ;; esac
cmp -s "$icon" "$APP/Contents/Resources/iTerm2.icns" || fail "the updater's icon is not upstream's iTerm2.icns"
cmp -s "$APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/iTerm2.icns" \
  || fail "the app has no AppIcon.icns equal to iTerm2.icns, so its nib's AppIcon image is missing"

[ "$fails" -eq 0 ] || { echo "updater-test: $fails failure(s)" >&2; exit 1; }
echo "updater-test: OK"
