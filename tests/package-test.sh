#!/bin/sh
# platform: host-agnostic -- packages and reads pkgs through shipyard's stevedore seams
# spec: BUILD.md "Package" -- build/package-pkg.sh makes iterm2-V.pkg: the base component first, then
#       dev.mavergreen.iterm2, installing the app at /Applications/Mavericks iTerm2.app, the family
#       updater and its agent, and a tree that holds only the manifest; it refuses an app that is not
#       this product's, is another version, or lacks the post-update helper; and what it makes passes
#       shipyard's artifact conformance. With a native build, the real app and updater are packaged too.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/msc.sh"
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-package-test.XXXXXX")   # platform: 10.9 BSD mktemp requires a template
trap 'rm -rf "$T"' EXIT
SOURCE_DATE_EPOCH=1761463588; export SOURCE_DATE_EPOCH
up=$(tr -d '[:space:]' < "$REPO_ROOT/UPSTREAM_VERSION")
V=$up-mavericks.7
upd_id=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" updater-bundle-id iterm2)
feed=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" feed iterm2)
name='Mavericks iTerm2.app'

plist() {
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>\n%s\n</dict></plist>\n' "$1"
}
fixture_app() { # DIR VERSION [ID] [no-helper]
  c="$1/iTerm2.app/Contents"; mkdir -p "$c/MacOS"
  printf '#!/bin/sh\n' > "$c/MacOS/iTerm2"; chmod 755 "$c/MacOS/iTerm2"
  [ "${4:-}" = no-helper ] || { printf '#!/bin/sh\n' > "$c/MacOS/restart-for-update"; chmod 755 "$c/MacOS/restart-for-update"; }
  plist "<key>CFBundleIdentifier</key><string>${3:-dev.mavergreen.iterm2.app}</string><key>CFBundleExecutable</key><string>iTerm2</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>$2</string>" > "$c/Info.plist"
}
fixture_updater() { # DIR VERSION [ID]
  c="$1/iterm2-updater.app/Contents"; mkdir -p "$c/MacOS"
  printf '#!/bin/sh\n' > "$c/MacOS/iterm2-updater"; chmod 755 "$c/MacOS/iterm2-updater"
  plist "<key>CFBundleIdentifier</key><string>${3:-$upd_id}</string><key>CFBundleExecutable</key><string>iterm2-updater</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>$2</string><key>SUFeedURL</key><string>$feed</string>" > "$c/Info.plist"
}
package() { sh "$REPO_ROOT/build/package-pkg.sh" "$@" > "$T/log" 2>&1; }
refused() { # MESSAGE ARGS... -- package-pkg.sh refuses, saying MESSAGE, and leaves nothing
  m=$1; shift
  rm -rf "$T/out"
  if package "$@"; then fail "accepted: $m"; return; fi
  grep -q "$m" "$T/log" || { cat "$T/log" >&2; fail "refused without saying: $m"; }
  [ -z "$(ls "$T/out" 2>/dev/null)" ] || fail "a refusal left $(ls "$T/out") behind"
}
conforms() { # DIST VERSION
  printf '## iTerm2 %s for Mavericks (%s)\n\n### What changed\n\n- Test.\n' "$up" "$2" > "$1/RELEASE_NOTES.md"
  sh "$SHIPYARD_SCRIPTS/stand-in-feeds.sh" "$1" "$2" > /dev/null
  facts=$(sh "$SHIPYARD_SCRIPTS/artifact-facts.sh" "$1" "$2") || { fail "artifact-facts could not read $1"; return; }
  printf '%s\n' "$facts" > "$T/facts"
  printf '%s\n' "$facts" | sh "$SHIPYARD_SCRIPTS/check-artifact-conformance.sh" > "$T/conformance" 2>&1 \
    || { cat "$T/conformance" >&2; fail "the pkg in $1 does not conform"; }
}

fixture_app "$T/f/app" "$V"; fixture_updater "$T/f/upd" "$V"
fixture_app "$T/f/other" "$V" org.example.other; fixture_app "$T/f/older" "$up-mavericks.6"
fixture_app "$T/f/nohelper" "$V" dev.mavergreen.iterm2.app no-helper
fixture_updater "$T/f/otherupd" "$V" org.example.updater

refused 'not the dev.mavergreen.iterm2.app bundle' --app "$T/f/other/iTerm2.app" --updater-app "$T/f/upd/iterm2-updater.app" --version "$V" --out "$T/out"
refused "is version $up-mavericks.6, not $V" --app "$T/f/older/iTerm2.app" --updater-app "$T/f/upd/iterm2-updater.app" --version "$V" --out "$T/out"
refused 'no Contents/MacOS/restart-for-update' --app "$T/f/nohelper/iTerm2.app" --updater-app "$T/f/upd/iterm2-updater.app" --version "$V" --out "$T/out"
refused "is not the $upd_id updater" --app "$T/f/app/iTerm2.app" --updater-app "$T/f/otherupd/iterm2-updater.app" --version "$V" --out "$T/out"

if package --app "$T/f/app/iTerm2.app" --updater-app "$T/f/upd/iterm2-updater.app" --version "$V" --out "$T/dist"; then
  [ -f "$T/dist/iterm2-$V.pkg" ] || fail "no $T/dist/iterm2-$V.pkg"
  conforms "$T/dist" "$V"
  grep -q "^installs .* Applications/Mavericks%20iTerm2.app/Contents/MacOS/restart-for-update$" "$T/facts" \
    || fail "the app is not at /Applications/$name"
  grep -q '^installs .* usr/local/mavergreen/iterm2/mavergreen.plist$' "$T/facts" || fail "no manifest in the tree"
  ! grep '^installs .* usr/local/mavergreen/iterm2/' "$T/facts" | grep -v 'mavergreen.plist$' | grep -q . \
    || fail "the tree holds more than the manifest"
else
  cat "$T/log" >&2; fail "package-pkg.sh refused good stand-ins"
fi

B=${ITERM_BUILD_DIR:-${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/$(basename "$REPO_ROOT")-native}
if [ -d "$B/iTerm2.app" ] && [ -d "$B/iterm2-updater.app" ]; then
  RV=$(sed -n 's/^\(.*-mavericks\.[0-9]*\)$/\1/p' "$B/VERSION" 2>/dev/null || true)
  [ -n "$RV" ] || RV=$("$(sh "$SHIPYARD_SCRIPTS/fetch_stevedore.sh")" plist get "$B/iTerm2.app/Contents/Info.plist" CFBundleShortVersionString)
  if package --app "$B/iTerm2.app" --updater-app "$B/iterm2-updater.app" --version "$RV" --out "$T/real"; then
    conforms "$T/real" "$RV"
  else
    cat "$T/log" >&2; fail "package-pkg.sh refused the native build"
  fi
else
  echo "package-test: no native build at $B; the real app is not packaged"
fi

[ "$fails" -eq 0 ] || { echo "package-test: $fails failure(s)" >&2; exit 1; }
echo "package-test: OK"
