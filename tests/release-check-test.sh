#!/bin/sh
# platform: macOS-only -- build/check-release-on-10.9.sh is meant for Mac OS X 10.9; its refusals are checked anywhere
# spec: INGREDIENTS.md "Conformance deviations" on-target:gui -- the 10.9 check refuses the wrong host and a
#       bad usage, and stops before installing anything when the pkg does not match its checksum, so a bad
#       dist never reaches sudo installer
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
C=$REPO_ROOT/build/check-release-on-10.9.sh
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-release-check-test.XXXXXX")   # platform: 10.9 BSD mktemp requires a template
trap 'rm -rf "$T"' EXIT
run() { rc=0; "$@" > "$T/out" 2>&1 || rc=$?; }

run sh "$C"
[ "$rc" = 2 ] && grep -q usage "$T/out" || fail "no VERSION is not a usage error"
run env MAVERICKS_CHECK_OS=11.7 sh "$C" 3.0.15-mavericks.1
[ "$rc" = 2 ] && grep -q 'run this on Mac OS X 10.9 (this is 11.7)' "$T/out" || fail "another macOS is not refused"

# spec: BUILD.md "Acceptance on 10.9" -- it would uninstall a copy someone already uses, so it refuses to start
mkdir -p "$T/installed"
run env MAVERICKS_CHECK_OS=10.9.5 MAVERICKS_CHECK_TREE="$T/installed" sh "$C" 3.0.15-mavericks.1
[ "$rc" = 2 ] && grep -q 'already installed' "$T/out" || { cat "$T/out" >&2; fail "an existing install is not refused"; }
! grep -q '^\(PASS\|FAIL\)' "$T/out" || fail "it ran steps despite an existing install"

# spec: BUILD.md "Acceptance on 10.9" -- standing in for upstream iTerm2 is only for a Mac without it
mkdir -p "$T/home/Library/Preferences"; : > "$T/home/Library/Preferences/com.googlecode.iterm2.plist"
run env MAVERICKS_CHECK_OS=10.9.5 MAVERICKS_CHECK_TREE="$T/none" HOME="$T/home" COEXIST_APPLICATIONS="$T/apps" \
  sh "$C" --stand-in-upstream 3.0.15-mavericks.1
[ "$rc" = 2 ] && grep -q 'upstream iTerm2 is here' "$T/out" || { cat "$T/out" >&2; fail "standing in over a real upstream is not refused"; }
! grep -q '^\(PASS\|FAIL\)' "$T/out" || fail "it ran steps when it should have refused to stand in"

mkdir "$T/dist"
printf 'not a pkg\n' > "$T/dist/iterm2-3.0.15-mavericks.1.pkg"
printf '0000000000000000000000000000000000000000000000000000000000000000  iterm2-3.0.15-mavericks.1.pkg\n' > "$T/dist/SHA256SUMS"
run env MAVERICKS_CHECK_OS=10.9.5 MAVERICKS_CHECK_TREE="$T/none" MAVERICKS_DIST="$T/dist" sh "$C" 3.0.15-mavericks.1
[ "$rc" = 1 ] && grep -q '^FAIL verify' "$T/out" || { cat "$T/out" >&2; fail "a pkg that does not match SHA256SUMS is not a FAIL"; }
! grep -q '^\(PASS\|FAIL\) install' "$T/out" || fail "it went on to install after the pkg failed to verify"

[ "$fails" -eq 0 ] || { echo "release-check-test: $fails failure(s)" >&2; exit 1; }
echo "release-check-test: OK"
