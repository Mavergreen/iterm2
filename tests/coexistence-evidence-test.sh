#!/bin/sh
# platform: macOS-only -- reads file sizes and times with stat -f.
# spec: BUILD.md "Identity and coexistence" -- build/coexistence-evidence.sh records upstream iTerm2's
#       preferences and support directories before this app runs and fails, naming what changed, if they
#       differ after; it never writes either.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-coexist-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
H="$T/home"; A="$H/Library/Application Support"
mkdir -p "$A/iTerm/Scripts" "$A/iTerm2/DynamicProfiles"
printf 'v\n' > "$A/iTerm/version.txt"; printf '{}\n' > "$A/iTerm2/DynamicProfiles/p.json"
# platform: 10.9's defaults has no export verb, so the fake answers only "read DOMAIN", as 10.9's does
printf '#!/bin/sh\n[ "$1" = read ] && [ "$2" = com.googlecode.iterm2 ] || exit 1\ncat "%s/prefs"\n' "$T" > "$T/fake-defaults"; chmod +x "$T/fake-defaults"
printf 'prefs-1\n' > "$T/prefs"
mkdir -p "$T/apps/iTerm.app/Contents"; printf 'x\n' > "$T/apps/iTerm.app/Contents/Info.plist"
mkdir -p "$H/Library/Preferences"; P="$H/Library/Preferences/com.googlecode.iterm2.plist"; : > "$P"
ev() { HOME="$H" COEXIST_DEFAULTS="$T/fake-defaults" COEXIST_APPLICATIONS="$T/apps" sh "$REPO_ROOT/build/coexistence-evidence.sh" "$@"; }

ev before "$T/e1" >/dev/null 2>&1 || fail "before exited nonzero"
ev after "$T/e1" >"$T/out" 2>&1 || fail "unchanged state: after exited nonzero: $(cat "$T/out")"
[ -s "$T/e1/before.txt" ] && grep -q 'DynamicProfiles/p.json' "$T/e1/before.txt" || fail "before does not list the support directories"

ev before "$T/e2" >/dev/null 2>&1
sleep 1; printf 'changed\n' >> "$A/iTerm2/DynamicProfiles/p.json"
if ev after "$T/e2" >"$T/out" 2>&1; then fail "a touched file passed"; fi
grep -q 'DynamicProfiles/p.json' "$T/out" || fail "a touched file is not named: $(cat "$T/out")"

ev before "$T/e3" >/dev/null 2>&1
printf 'prefs-2\n' > "$T/prefs"
if ev after "$T/e3" >"$T/out" 2>&1; then fail "changed upstream preferences passed"; fi
grep -q 'com.googlecode.iterm2' "$T/out" || fail "changed upstream preferences are not named"

ev before "$T/e4" >/dev/null 2>&1
mkdir -p "$A/iTerm/Scripts/new"; : > "$A/iTerm/Scripts/AutoLaunch.scpt"
if ev after "$T/e4" >"$T/out" 2>&1; then fail "a new file passed"; fi
grep -q 'AutoLaunch.scpt' "$T/out" || fail "a new file is not named"

ev after "$T/never" >/dev/null 2>&1 && fail "after without before passed"
: > "$T/prefs"
ev before "$T/e5" >"$T/out" 2>&1 && fail "unreadable upstream preferences were recorded as if read"

# spec: BUILD.md "Acceptance on 10.9" -- a Mac without upstream iTerm2 (the 10.9 guest) has no such domain:
#       that is recorded as absent, and the domain appearing afterwards is a change
rm -f "$P"
ev before "$T/e6" >"$T/out" 2>&1 || fail "no upstream preferences at all could not be recorded: $(cat "$T/out")"
grep -q '^absent prefs com.googlecode.iterm2$' "$T/e6/before.txt" 2>/dev/null || fail "missing upstream preferences are not recorded as absent"
ev after "$T/e6" >/dev/null 2>&1 || fail "still-absent upstream preferences are a change"
printf 'prefs-1\n' > "$T/prefs"; : > "$P"
if ev after "$T/e6" >"$T/out" 2>&1; then fail "upstream preferences that appeared passed"; fi
grep -q 'com.googlecode.iterm2' "$T/out" || fail "preferences that appeared are not named"

# spec: BUILD.md "Acceptance on 10.9" -- upstream's app is part of its state too
ev before "$T/e7" >/dev/null 2>&1 || fail "before failed with upstream's app present"
grep -q 'iTerm.app/Contents/Info.plist' "$T/e7/before.txt" 2>/dev/null || fail "before does not list upstream's app"
sleep 1; printf 'y\n' >> "$T/apps/iTerm.app/Contents/Info.plist"
if ev after "$T/e7" >"$T/out" 2>&1; then fail "a changed upstream app passed"; fi
grep -q 'iTerm.app/Contents/Info.plist' "$T/out" || fail "a changed upstream app is not named"

[ "$fails" -eq 0 ] || { echo "coexistence-evidence-test: $fails failure(s)" >&2; exit 1; }
echo "coexistence-evidence-test: OK"
