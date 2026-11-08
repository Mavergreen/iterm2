#!/bin/sh
# platform: host-agnostic -- shipyard's stevedore seams build and read the pkg
#   usage: build/package-pkg.sh --app APP --updater-app UPDATER --version V --out DIR
#          Packages APP (the build's iTerm2.app) as /Applications/Mavericks iTerm2.app and UPDATER
#          (iterm2-updater.app) as the family updater, with the tree /usr/local/mavergreen/iterm2 holding
#          the manifest, as DIR/iterm2-V.pkg: dev.mavergreen.base first, then dev.mavergreen.iterm2, with
#          the 10.9.5 floor. V is UPSTREAM_VERSION with its -mavericks.N, and both bundles' version. The
#          pkg appears in DIR only once it is made, and the updater must carry the registry's identity; APP and UPDATER are not changed. A caller without git
#          exports SOURCE_DATE_EPOCH, which stamps every file's mtime.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/build/msc.sh"
fail() { echo "package-pkg: $*" >&2; exit 1; }
usage() { printf 'usage: build/package-pkg.sh --app APP --updater-app UPDATER --version V --out DIR\n' >&2; exit 2; }
app=; updater=; V=; out=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app|--updater-app|--version|--out) [ "$#" -ge 2 ] || usage ;;
    *) usage ;;
  esac
  case "$1" in
    --app) app=$2 ;;
    --updater-app) updater=$2 ;;
    --version) V=$2 ;;
    --out) out=$2 ;;
  esac
  shift 2
done
[ -n "$app" ] && [ -n "$updater" ] && [ -n "$V" ] && [ -n "$out" ] || usage
short=iterm2
name='Mavericks iTerm2.app'
id=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" identifier "$short" 2>/dev/null) ||
  fail "the shipyard at $SHIPYARD_SCRIPTS does not register $short"
up=$(tr -d '[:space:]' < "$REPO_ROOT/UPSTREAM_VERSION")
case "$V" in
  "$up"-mavericks.[1-9]*) ;;
  *) fail "--version $V is not UPSTREAM_VERSION $up with a -mavericks.N" ;;
esac
STEVEDORE=$(sh "$SHIPYARD_SCRIPTS/fetch_stevedore.sh") || fail 'cannot fetch stevedore'
info() { "$STEVEDORE" plist get "$1/Contents/Info.plist" "$2" 2>/dev/null; }
[ "$(info "$app" CFBundleIdentifier || true)" = dev.mavergreen.iterm2.app ] ||
  fail "$app is not the dev.mavergreen.iterm2.app bundle"
appv=$(info "$app" CFBundleShortVersionString || true)
[ "$appv" = "$V" ] || fail "$app is version $appv, not $V"
[ -f "$app/Contents/MacOS/restart-for-update" ] && [ -x "$app/Contents/MacOS/restart-for-update" ] ||
  fail "$app has no Contents/MacOS/restart-for-update, the updater's post-update helper"
upd_id=$(sh "$SHIPYARD_SCRIPTS/product-name.sh" updater-bundle-id "$short")
[ "$(info "$updater" CFBundleIdentifier || true)" = "$upd_id" ] || fail "$updater is not the $upd_id updater"
updv=$(info "$updater" CFBundleShortVersionString || true)
[ "$updv" = "$V" ] || fail "$updater is version $updv, not $V"

mkdir -p "$out"
out=$(CDPATH= cd "$out" && pwd)
pkg=$out/$short-$V.pkg
[ ! -e "$pkg" ] || fail "$pkg already exists"
work=$(mktemp -d "${TMPDIR:-/tmp}/iterm2-package.XXXXXX")   # platform: 10.9 BSD mktemp requires a template
trap 'rm -rf "$work"' EXIT
root=$work/root
mkdir -p "$root/Applications/$name" "$root/usr/local/mavergreen/$short" "$work/scripts" "$work/component"
COPYFILE_DISABLE=1 cp -Rp "$app/Contents" "$root/Applications/$name/Contents"
sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage "$root" --product "$short" --name 'iTerm2 for Mavericks' \
  --version "$V" --updater-app "$updater" --scripts-out "$work/scripts" >&2
find "$root" -name '._*' -exec rm -f {} + 2> /dev/null || true
comp=$work/component/$short.pkg
sh "$SHIPYARD_SCRIPTS/build_component_pkg.sh" --root "$root" --identifier "$id" --version "$V" \
  --install-location / --scripts "$work/scripts" --out "$comp" > /dev/null
sh "$SHIPYARD_SCRIPTS/set_install_floor.sh" --identifier "$id" --title 'iTerm2 for Mavericks' \
  --component "$comp" --out "$work/product.pkg" --host-arch x86_64 --min-os 10.9.5 --require-scripts > /dev/null
mv "$work/product.pkg" "$pkg"
printf 'package-pkg: %s\n' "$pkg" >&2
