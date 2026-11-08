#!/bin/sh
# platform: macOS-only -- prepares the pinned source with shipyard's fetch and patch scripts.
# spec: BUILD.md "Identity and coexistence" -- this app runs beside upstream iTerm2 and shares none of its
#       writable state: its support directory follows its own CFBundleName, never the executable name
#       both apps have or upstream's literal "iTerm" directory (whose AutoLaunch script runs at every
#       launch), and no upstream bundle id stands for this app.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-identity-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
. "$REPO_ROOT/build/msc.sh"
v() { sed -n "s/^$1=//p" "$REPO_ROOT/components/iterm2/version"; }
sh "$SHIPYARD_SCRIPTS/fetch_pinned_source.sh" "$(v REPO)" "$(v DIGEST)" "$(v SHA256)" "$T/src" 2>/dev/null \
  || { echo "identity-test: the pinned source did not fetch" >&2; exit 1; }
sh "$SHIPYARD_SCRIPTS/apply_patches.sh" "$T/src" "$REPO_ROOT/patches" >/dev/null 2>&1 \
  || { echo "identity-test: patches/ does not apply" >&2; exit 1; }
S="$T/src/sources"

method() { # FILE SELECTOR-LINE -- the body of the method whose declaration line starts with SELECTOR-LINE
  awk -v sel="$2" 'index($0, sel) == 1 { on = 1 } on { print } on && /^}/ { exit }' "$1"
}
for m in '- (NSString *)applicationSupportDirectory {' '- (NSString *)legacyApplicationSupportDirectory {'; do
  body=$(method "$S/NSFileManager+iTerm.m" "$m")
  [ -n "$body" ] || { fail "identity: the support directory follows CFBundleName ($m is missing)"; continue; }
  printf '%s\n' "$body" | grep -q 'kCFBundleNameKey' && ! printf '%s\n' "$body" | grep -qE 'kCFBundleExecutableKey|@"iTerm"' \
    || fail "identity: the support directory follows CFBundleName ($m)"
done

# Each allowed use is pinned by file and its exact line, so a new use in an allowlisted file still fails.
cat > "$T/allowed" <<'ALLOWED'
AppleScriptTest.m:static NSString *const kTestBundleId = @"com.googlecode.iterm2.applescript";
SCPFile.m:static NSString *const kSCPFileErrorDomain = @"com.googlecode.iterm2.SCPFile";
TerminalFile.m:    return [NSError errorWithDomain:@"com.googlecode.iterm2.TerminalFile"
iTermApplicationDelegate.m: *    open file "/com.googlecode.iterm2/commandmode"
iTermRemotePreferences.m:            @"copy ~/Library/Preferences/com.googlecode.iterm2.plist to "
ALLOWED
left=$(grep -rE 'com\.googlecode\.iterm2|net\.sourceforge\.iterm' "$S" --include='*.m' --include='*.h' \
         | sed "s|^$S/||" | grep -vxF -f "$T/allowed" || :)
[ -z "$left" ] || fail "identity: no upstream id stands for this app: $left"
grep -q 'objectForKey:@"NSApplicationBundleIdentifier"\] isEqualToString:\[\[NSBundle mainBundle\] bundleIdentifier\]' \
  "$S/HotkeyWindowController.m" || fail "identity: no upstream id stands for this app (the hotkey window's own-app check)"
grep -q 'handlerId isEqualToString:\[\[NSBundle mainBundle\] bundleIdentifier\]' "$S/iTermLaunchServices.m" \
  || fail "identity: no upstream id stands for this app (the URL handler's own-app check)"

# spec: Review Focus 4 -- with both directories the same, legacy notes exist only where the new ones are,
#       so the migration must keep moving only when the new file is absent
grep -q '\[fileManager fileExistsAtPath:\[self legacyFilename\]\] && !\[fileManager fileExistsAtPath:\[self filename\]\]' "$S/ToolNotes.m" \
  || fail "identity: notes survive when the directories coincide"

[ "$fails" -eq 0 ] || { echo "identity-test: $fails failure(s)" >&2; exit 1; }
echo "identity-test: OK"
