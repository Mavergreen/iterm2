#!/bin/sh
# platform: macOS-only -- Installer, PlistBuddy, sandbox-exec and the installed product; meant for Mac OS X 10.9
#   usage: build/check-release-on-10.9.sh [--drivers TAR] [--repo-tests] [--stand-in-upstream] VERSION
#          Run on Mac OS X 10.9 as the user who will use iTerm2, not as root (it runs sudo itself), with
#          no Mavericks iTerm2 running or installed: it uninstalls what it installs, so it refuses to start
#          where Mavericks iTerm2 is already installed. Checks DIST/iterm2-VERSION.pkg (DIST is MAVERICKS_DIST, default
#          the checkout's dist/) against DIST/SHA256SUMS, then without a GUI session:
#            - with --stand-in-upstream, on a Mac that has no upstream iTerm2 (the CI guest), first plants
#              state where upstream's would be: an app, its preferences and support files, so that the
#              coexistence check compares something; it refuses where any upstream state exists;
#            - records upstream iTerm2's state (build/coexistence-evidence.sh);
#            - installs the pkg, and checks the manifest, the app's identity, version and floor, the
#              updater and its agent, and `mavergreen check`;
#            - runs the app's post-update helper with no instance running: it exits 0 and launches nothing;
#            - installs the pkg again over itself, and checks the same;
#            - with --drivers, unpacks TAR (build/pack-drivers.sh) and runs every driver, the image
#              decoder's with the installed image_decoder and its sandbox profile beside it;
#            - with --repo-tests, runs the repo's suite with shipyard's run-repo-tests.sh;
#            - uninstalls with `mavergreen uninstall iterm2`, checks that nothing of it is left, and that
#              upstream iTerm2's state is unchanged.
#          One PASS/FAIL line per step; exit 1 if any failed, 2 on a usage error or the wrong host.
# spec: INGREDIENTS.md "Conformance deviations" on-target:gui -- the guest has no GUI session, so the app's
#       windows are checked by hand (SMOKE.md); everything here runs without one
set -u
here=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
drivers=; repo_tests=false; stand_in=false
while [ "$#" -gt 1 ]; do
  case "$1" in
    --stand-in-upstream) stand_in=true; shift ;;
    --drivers) [ "$#" -ge 3 ] || break; drivers=$2; shift 2 ;;
    --repo-tests) repo_tests=true; shift ;;
    *) break ;;
  esac
done
[ "$#" -eq 1 ] && [ -n "$1" ] ||
  { echo 'usage: check-release-on-10.9.sh [--drivers TAR] [--repo-tests] [--stand-in-upstream] VERSION   (e.g. 3.0.15-mavericks.1)' >&2; exit 2; }
V=$1
os=${MAVERICKS_CHECK_OS:-$(sw_vers -productVersion 2>/dev/null)}
case "$os" in 10.9|10.9.*) ;; *) echo "check-release-on-10.9.sh: run this on Mac OS X 10.9 (this is $os)" >&2; exit 2 ;; esac
[ "$(id -u)" != 0 ] || { echo 'check-release-on-10.9.sh: run this as the user, not as root; it runs sudo itself' >&2; exit 2; }
dist=${MAVERICKS_DIST:-$repo/dist}
pkg=$dist/iterm2-$V.pkg
app='/Applications/Mavericks iTerm2.app'
tree=${MAVERICKS_CHECK_TREE:-/usr/local/mavergreen/iterm2}
[ ! -e "$tree" ] || { echo "check-release-on-10.9.sh: Mavericks iTerm2 is already installed ($tree), and this check uninstalls what it installs; run 'sudo mavergreen uninstall iterm2' first" >&2; exit 2; }
APPS=${COEXIST_APPLICATIONS:-/Applications}
AS="$HOME/Library/Application Support"
if $stand_in; then
  for f in "$APPS/iTerm.app" "$HOME/Library/Preferences/com.googlecode.iterm2.plist" "$AS/iTerm" "$AS/iTerm2"; do
    [ ! -e "$f" ] || { echo "check-release-on-10.9.sh: upstream iTerm2 is here ($f); --stand-in-upstream is only for a Mac without it" >&2; exit 2; }
  done
fi
. "$repo/build/msc.sh"
upd=/$(sh "$SHIPYARD_SCRIPTS/product-name.sh" updater-app iterm2)
label=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" agent-label iterm2)
w=$(mktemp -d /tmp/itermcheck.XXXXXX) || exit 1   # platform: 10.9 BSD mktemp requires a template
bad=0
step() {
  name=$1; shift
  if ( "$@" ) > "$w/$name.log" 2>&1; then echo "PASS $name"; else
    echo "FAIL $name (log: $w/$name.log)"; tail -n 20 "$w/$name.log" | sed 's/^/    /'; bad=1
  fi
}
trap 'if [ "$bad" = 0 ]; then rm -rf "$w"; else echo "logs kept in $w"; fi' EXIT
pb() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }

verify() {
  [ -f "$pkg" ] || { echo "no $pkg"; return 1; }
  want=$(awk -v f="iterm2-$V.pkg" '$2 == f { print $1 }' "$dist/SHA256SUMS")
  [ -n "$want" ] || { echo "$dist/SHA256SUMS does not list iterm2-$V.pkg"; return 1; }
  [ "$(shasum -a 256 "$pkg" | cut -d' ' -f1)" = "$want" ] || { echo "$pkg does not match SHA256SUMS"; return 1; }
}
no_instance() { ! pgrep -f "$app/Contents/MacOS/iTerm2" > /dev/null || { echo 'Mavericks iTerm2 is running; quit it first'; return 1; }; }
stand_in_upstream() {
  mkdir -p "$APPS/iTerm.app/Contents/MacOS" "$AS/iTerm/Scripts" "$AS/iTerm2/DynamicProfiles" || return 1
  printf 'stand-in for upstream iTerm2\n' > "$APPS/iTerm.app/Contents/Info.plist"
  printf 'stand-in\n' > "$AS/iTerm/version.txt"; printf '{}\n' > "$AS/iTerm2/DynamicProfiles/stand-in.json"
  defaults write com.googlecode.iterm2 MavericksStandIn -bool YES
}
before() { sh "$repo/build/coexistence-evidence.sh" before "$w/coexistence"; }
after() { sh "$repo/build/coexistence-evidence.sh" after "$w/coexistence"; }
install() { sudo /usr/sbin/installer -pkg "$pkg" -target /; }
installed() {
  got=$(pb "$tree/mavergreen.plist" version) || return 1
  [ "$got" = "$V" ] || { echo "the installed manifest says version $got, not $V"; return 1; }
  [ "$(pb "$app/Contents/Info.plist" CFBundleIdentifier)" = dev.mavergreen.iterm2.app ] || { echo "$app is not dev.mavergreen.iterm2.app"; return 1; }
  got=$(pb "$app/Contents/Info.plist" CFBundleShortVersionString) || return 1
  [ "$got" = "$V" ] || { echo "the installed app is version $got, not $V"; return 1; }
  [ "$(pb "$app/Contents/Info.plist" LSMinimumSystemVersion)" = 10.9 ] || { echo "the app's floor is not 10.9"; return 1; }
  got=$(pb "$upd/Contents/Info.plist" CFBundleShortVersionString) || { echo "no updater at $upd"; return 1; }
  [ "$got" = "$V" ] || { echo "the installed updater is version $got, not $V"; return 1; }
  [ -f "/Library/LaunchAgents/$label.plist" ] || { echo "no LaunchAgent $label"; return 1; }
  /usr/local/bin/mavergreen check || { echo 'mavergreen check failed'; return 1; }
  /usr/local/bin/mavergreen list | grep -q '^iterm2 ' || { echo 'mavergreen list does not show iterm2'; return 1; }
}
helper_alone() {
  "$app/Contents/MacOS/restart-for-update" || { echo 'the helper failed with no instance running'; return 1; }
  sleep 2
  ! pgrep -f "$app/Contents/MacOS/iTerm2" > /dev/null || { echo 'the helper launched iTerm2'; return 1; }
}
run_drivers() {
  d=$w/drivers; mkdir -p "$d"
  tar -xf "$drivers" -C "$d" || { echo "cannot unpack $drivers"; return 1; }
  cp "$app/Contents/Resources/image_decoder" "$app/Contents/Resources/image_decoder.sb" "$d/" || return 1
  n=0
  for t in "$d"/driver-*; do
    [ -x "$t" ] || continue
    n=$((n + 1))
    echo "== $(basename "$t")"
    (cd "$d" && ITERM_DRIVER_PNG="$d/BigArrow.png" "$t") || { echo "$(basename "$t") failed"; return 1; }
  done
  [ "$n" -gt 0 ] || { echo "no driver in $drivers"; return 1; }
}
suite() { sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"; }
uninstall() { sudo /usr/local/bin/mavergreen uninstall iterm2; }
gone() {
  for f in "$app" "$upd" "/Library/LaunchAgents/$label.plist" "$tree"; do
    [ ! -e "$f" ] || { echo "$f is still installed"; return 1; }
  done
}

step verify verify
step not-running no_instance
! $stand_in || step stand-in-upstream stand_in_upstream
step coexistence-before before
# spec: tests/release-check-test.sh -- nothing is installed unless the pkg verified, nothing of ours was
#       running and upstream's state was recorded
[ "$bad" = 0 ] || { echo 'not installing: a check before installation failed'; exit 1; }
step install install
step installed installed
step helper-alone helper_alone
step reinstall install
step reinstalled installed
[ -z "$drivers" ] || step drivers run_drivers
! $repo_tests || step repo-tests suite
step uninstall uninstall
step uninstalled gone
step coexistence-after after
exit "$bad"
