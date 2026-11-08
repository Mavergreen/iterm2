#!/bin/sh
# platform: macOS-only -- fetches the pinned source with shipyard's scripts and syntax-checks with clang22.
# spec: BUILD.md "Dependency dispositions" -- patches 0002-0004 remove every Growl, NMSSH and old-Sparkle reference from the
#       pinned source, each touching only the files its contract lists, while the callers and the
#       stored names (GrowlTrigger, PTYSession, the "BM Growl" key) stay byte-identical; the patch set
#       is exactly 0001-0012; the updater bundle id is never a literal; the nib shim stands alone.
set -eu
# platform: modern macOS's en_US.UTF-8 sort ignores case and 10.9's sorts by byte; the file lists compare sorted
export LC_ALL=C
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-dispositions-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
. "$REPO_ROOT/build/msc.sh"

v() { sed -n "s/^$1=//p" "$REPO_ROOT/components/iterm2/version"; }
sh "$SHIPYARD_SCRIPTS/fetch_pinned_source.sh" "$(v REPO)" "$(v DIGEST)" "$(v SHA256)" "$T/pristine" 2>/dev/null \
  || { echo "dispositions-test: the pinned source did not fetch" >&2; exit 1; }
cp -R "$T/pristine" "$T/src"

expect='0001-image-decoder-arc-bridges.patch
0002-notifications-user-notification-center.patch
0003-scp-transfers-unavailable.patch
0004-family-updater.patch
0005-terminal-file-extern.patch
0006-coexist-with-upstream.patch
0007-tmux-send-control-c-first.patch
0008-tmux-no-server-values-in-commands.patch
0009-no-dns-lookup-on-hover.patch
0010-own-session-socket-prefix.patch
0011-image-decoder-real-path.patch
0012-url-links-plain-names-only.patch'
[ "$(cd "$REPO_ROOT/patches" && ls *.patch)" = "$expect" ] || fail "the patch set is not exactly 0001-0012"

touches() { # PATCH -- the files a patch writes, sorted, one per line
  sed -n 's|^+++ b/||p' "$REPO_ROOT/patches/$1" | sort | tr '\n' ' '
}
[ "$(touches 0001-image-decoder-arc-bridges.patch)" = 'image_decoder/image_decoder.m ' ] \
  || fail "0001 touches other files: $(touches 0001-image-decoder-arc-bridges.patch)"
[ "$(touches 0002-notifications-user-notification-center.patch)" = 'sources/iTermGrowlDelegate.h sources/iTermGrowlDelegate.m ' ] \
  || fail "0002 touches other files"
[ "$(touches 0003-scp-transfers-unavailable.patch)" = 'sources/SCPFile.m ' ] || fail "0003 touches other files"
[ "$(touches 0004-family-updater.patch)" = 'sources/GeneralPreferencesViewController.m sources/iTermApplicationDelegate.m sources/iTermController.h sources/iTermController.m ' ] \
  || fail "0004 touches other files"
[ "$(touches 0005-terminal-file-extern.patch)" = 'sources/TerminalFile.h ' ] || fail "0005 touches other files"
[ "$(touches 0006-coexist-with-upstream.patch)" = 'sources/HotkeyWindowController.m sources/NSFileManager+iTerm.m sources/iTermLaunchServices.m ' ] \
  || fail "0006 touches other files"
[ "$(touches 0007-tmux-send-control-c-first.patch)" = 'sources/PTYSession.m sources/TmuxController.h sources/TmuxController.m ' ] \
  || fail "0007 touches other files"
[ "$(touches 0008-tmux-no-server-values-in-commands.patch)" = 'sources/PTYSession.m sources/TmuxController.h sources/TmuxController.m sources/TmuxDashboardController.m sources/TmuxSessionsTable.h sources/TmuxSessionsTable.m sources/TmuxWindowsTable.h sources/TmuxWindowsTable.m ' ] \
  || fail "0008 touches other files"
[ "$(touches 0009-no-dns-lookup-on-hover.patch)" = 'iTerm2.xcodeproj/project.pbxproj sources/PTYTextView.m sources/iTermAdvancedSettingsModel.h sources/iTermAdvancedSettingsModel.m sources/iTermTextDrawingHelper.h sources/iTermTextDrawingHelper.m ' ] \
  && [ "$(grep -B1 '^+++ /dev/null$' "$REPO_ROOT/patches/0009-no-dns-lookup-on-hover.patch" | sed -n 's|^--- a/||p' | sort | tr '\n' ' ')" = 'sources/AsyncHostLookupController.h sources/AsyncHostLookupController.m ' ] \
  || fail "0009 touches other files"
[ "$(touches 0010-own-session-socket-prefix.patch)" = 'sources/iTermFileDescriptorSocketPath.c ' ] || fail "0010 touches other files"
[ "$(touches 0011-image-decoder-real-path.patch)" = 'sources/iTermImageDecoderDriver.m ' ] || fail "0011 touches other files"
[ "$(touches 0012-url-links-plain-names-only.patch)" = 'sources/PseudoTerminal.m sources/iTermController.m ' ] || fail "0012 touches other files"

if sh "$SHIPYARD_SCRIPTS/apply_patches.sh" "$T/src" "$REPO_ROOT/patches" >"$T/log" 2>&1; then
  left=$(grep -rIlE 'Growl/Growl\.h|GrowlApplicationBridge|NMSSH/|NMSSH[A-Z]|libssh2[_.]|Sparkle/|SUFeedURL([^A-Za-z]|$)|refreshSoftwareUpdateUserDefaults' \
           "$T/src/sources" "$T/src/image_decoder" --include='*.h' --include='*.m' --include='*.c' || :)
  [ -z "$left" ] || fail "references remain after patching: $left"
  for f in sources/GrowlTrigger.m sources/GrowlTrigger.h sources/ITAddressBookMgr.h \
           sources/TransferrableFile.m sources/FileTransferManager.m; do
    cmp -s "$T/pristine/$f" "$T/src/$f" || fail "$f changed"
  done
  # spec: SECURITY.md CVE-2023-46300, CVE-2019-9535 -- PTYSession.m carries the tmux security fixes (0007,
  #       0008) and nothing from 0002-0004
  mkdir -p "$T/only-tmux/sources"; cp "$T/pristine/sources/PTYSession.m" "$T/only-tmux/sources/"
  ok=yes
  for p in 0007-tmux-send-control-c-first.patch 0008-tmux-no-server-values-in-commands.patch; do
    sed -n '/^--- a\/sources\/PTYSession.m$/,/^--- a\//p' "$REPO_ROOT/patches/$p" | sed '$ { /^--- a\//d; }' > "$T/hunks.patch"
    (cd "$T/only-tmux" && patch -s -p1 < "$T/hunks.patch") || ok=no
  done
  [ "$ok" = yes ] && cmp -s "$T/only-tmux/sources/PTYSession.m" "$T/src/sources/PTYSession.m" \
    || fail "sources/PTYSession.m changed beyond 0007 and 0008"
  grep -q '@ITERM_UPDATER_BUNDLE_ID' "$T/src/sources/iTermApplicationDelegate.m" \
    || fail "checkForUpdates: does not use the ITERM_UPDATER_BUNDLE_ID definition"
  ! grep -rq 'dev\.mavergreen' "$T/src/sources" || fail "a Mavergreen identity is a literal in the source"
  grep -q 'NSWorkspaceLaunchConfigurationArguments: @\[ @"--user" \]' "$T/src/sources/iTermApplicationDelegate.m" \
    || fail "the updater is not launched with --user"
  grep -q 'deliverNotification:' "$T/src/sources/iTermGrowlDelegate.m" || fail "notifications are not delivered"
  grep -q 'removeDeliveredNotification:notification' "$T/src/sources/iTermGrowlDelegate.m" \
    || fail "a clicked notification is not removed from Notification Center"
  # spec: BUILD.md "Updates" -- upstream's restart flag stays, heard from the family updater's helper
  grep -q '\[\[NSDistributedNotificationCenter defaultCenter\] addObserver:self' "$T/src/sources/iTermApplicationDelegate.m" \
    && grep -q 'name:@"SUUpdaterWillRestartNotificationName"' "$T/src/sources/iTermApplicationDelegate.m" \
    || fail "Sparkle's will-restart notification is not heard on the distributed center"
  grep -q 'itad.sparkleRestarting' "$T/src/sources/iTermController.m" \
    || fail "a quit for an update no longer leaves restorable sessions running"
  grep -q '@ITERM_RELEASES_URL' "$T/src/sources/iTermApplicationDelegate.m" \
    || fail "the updater alert does not name the release page (ITERM_RELEASES_URL)"
  grep -q 'is not installed' "$T/src/sources/iTermApplicationDelegate.m" \
    && grep -q 'could not be opened' "$T/src/sources/iTermApplicationDelegate.m" \
    || fail "the updater alert does not tell a missing updater from one that failed to open"
  grep -q 'iTermFamilyVersionIsNewer' "$T/src/sources/iTermApplicationDelegate.m" \
    || fail "version:newerThan: does not use the product's comparator"
  awk '/^- \(void\)stop \{/,/^\}/' "$T/src/sources/SCPFile.m" | grep -q 'kTransferrableFileStatusFinishedWithError' \
    || fail "stopping a failed scp transfer can overwrite its error state"
  grep -q 'kTransferrableFileStatusStarting' "$T/src/sources/SCPFile.m" \
    && grep -q 'didFinishTransmissionWithError:error' "$T/src/sources/SCPFile.m" \
    || fail "an scp transfer does not end in a reported error"
else
  cat "$T/log" >&2; fail "patches 0001-0012 do not apply to the pinned source without fuzz"
fi

for c in /usr/local/mavergreen/clang22/bin/clang /usr/local/mavergreen/clang22-cross/bin/clang; do
  [ -x "$c" ] && CLANG22=$c && break
done
if [ -n "${CLANG22:-}" ]; then
  # spec: BUILD.md "Dependency dispositions" -- with the app target's flags: the pinned SDK, x86_64, 10.9, c99, no ARC
  SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
  "$CLANG22" -fsyntax-only -x objective-c -fno-objc-arc -std=c99 -arch x86_64 -isysroot "$SDK" \
    -mmacosx-version-min=10.9 -Werror "$REPO_ROOT/product/SUUpdater.m" >"$T/cc" 2>&1 \
    || { cat "$T/cc" >&2; fail "product/SUUpdater.m does not compile"; }
else
  echo "dispositions-test: no clang22 installed (as in the 10.9 acceptance guest); SUUpdater.m is not compiled"
fi
[ "$(grep -c '^- .*{$' "$REPO_ROOT/product/SUUpdater.m" 2>/dev/null)" = 1 ] \
  || fail "the SUUpdater shim must define exactly one method, checkForUpdates:"

# spec: BUILD.md "Targets" -- the source lists come from the Xcode project, whose exporter refuses a source that
#       does not exist, so a patch that deletes a file also drops it from the project, as upstream did
for p in "$REPO_ROOT"/patches/*.patch; do
  grep -B1 '^+++ /dev/null$' "$p" | sed -n 's|^--- a/sources/||p' | while read -r gone; do
    ! grep -qF "/* $gone" "$T/src/iTerm2.xcodeproj/project.pbxproj" || echo "$(basename "$p") deletes sources/$gone, which the Xcode project still names"
  done
done > "$T/stale"
[ ! -s "$T/stale" ] || { cat "$T/stale" >&2; fail "the Xcode project names a source a patch deletes"; }

[ "$fails" -eq 0 ] || { echo "dispositions-test: $fails failure(s)" >&2; exit 1; }
echo "dispositions-test: OK"
