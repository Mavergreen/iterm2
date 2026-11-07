#!/bin/sh
# platform: macOS-only -- reads installed Mavergreen product manifests with plutil, and the product
#           builds only for macOS (natively on 10.9, or cross on a modern Mac).
#   usage: prepare-inputs.sh OUTPUT_ROOT
#          Prepares every input the CMake build reads, from this checkout's pins, and writes
#          OUTPUT_ROOT/inputs.cmake and OUTPUT_ROOT/inputs.json only when all of them verify:
#            - components/iterm2/version: the pinned commit, fetched fresh into OUTPUT_ROOT/source by
#              shipyard's fetch_pinned_source.sh and patched with patches/*.patch (apply_patches.sh);
#            - components/iterm2-resources/version: upstream's release ZIP, verified by SHA-256 into
#              the source cache (shipyard_fetch_verified);
#            - UPSTREAM_VERSION agrees with the source REF (v<version>) and the resource VERSION;
#            - shipyard's released modules this build consumes are installed beside its scripts;
#            - the clang22 for this host's mode (clang22 native, clang22-cross on a modern Mac) and
#              Recaulk are installed at exactly components/clang22/version and components/recaulk/version,
#              read from <MAVERGREEN_ROOT>/usr/local/mavergreen/<short>/mavergreen.plist.
#          A pin file is data: each value must match its own pattern, and none is evaluated. Any failure
#          removes OUTPUT_ROOT's inputs files first, so no earlier run's inputs survive a failed one.
#          OUTPUT_ROOT must lie outside this checkout. MAVERGREEN_ROOT (default /) relocates the
#          installed products, and MAVERICKS_SOURCE_CACHE the download cache, for tests.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
die() { echo "prepare-inputs: $*" >&2; exit 1; }
[ "$#" -eq 1 ] || { echo 'usage: prepare-inputs.sh OUTPUT_ROOT' >&2; exit 2; }
case "$1" in /*) ;; *) die "OUTPUT_ROOT must be absolute: $1" ;; esac
mkdir -p "$1"
OUT=$(CDPATH= cd "$1" && pwd -P)
case "$OUT/" in "$(CDPATH= cd "$REPO_ROOT" && pwd -P)/"*) die "OUTPUT_ROOT is inside the checkout: $OUT" ;; esac
rm -f "$OUT/inputs.cmake" "$OUT/inputs.json"
ROOT=${MAVERGREEN_ROOT:-/}
ROOT=${ROOT%/}
CACHE=${MAVERICKS_SOURCE_CACHE:-$HOME/Library/Caches/mavericks-sources}

pin() {
  [ -f "$REPO_ROOT/$1" ] || die "$1 is missing"
  _v=$(sed -n "s/^$2=//p" "$REPO_ROOT/$1")
  [ "$(printf '%s\n' "$_v" | wc -l | tr -d ' ')" = 1 ] && [ -n "$_v" ] || die "$1: exactly one $2= line is required"
  printf '%s\n' "$_v" | grep -Eqx "$3" || die "$1: $2 does not have the form ${3}: $_v"
  printf '%s' "$_v"
}
line() { # FILE PATTERN -- a one-line pin file's value
  [ -f "$REPO_ROOT/$1" ] || die "$1 is missing"
  _v=$(cat "$REPO_ROOT/$1")
  printf '%s\n' "$_v" | grep -Eqx "$2" || die "$1 does not have the form $2"
  printf '%s' "$_v"
}
HEX40='[0-9a-f]{40}'
HEX64='[0-9a-f]{64}'
VER='[0-9]+(\.[0-9]+)*'
TAG='[0-9][0-9A-Za-z.]*(-mavericks\.[1-9][0-9]*)?'
src_repo=$(pin components/iterm2/version REPO 'https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+')
src_ref=$(pin components/iterm2/version REF 'v[0-9A-Za-z._-]+')
src_digest=$(pin components/iterm2/version DIGEST "$HEX40")
src_sha=$(pin components/iterm2/version SHA256 "$HEX64")
res_url=$(pin components/iterm2-resources/version URL '(https|file)://[A-Za-z0-9._~/%+-]+\.zip')
res_sha=$(pin components/iterm2-resources/version SHA256 "$HEX64")
res_version=$(pin components/iterm2-resources/version VERSION "$VER")
upstream=$(line UPSTREAM_VERSION "$VER")
clang_pin=$(line components/clang22/version "$TAG")
recaulk_pin=$(line components/recaulk/version "$TAG")
[ "$src_ref" = "v$upstream" ] || die "components/iterm2/version REF $src_ref is not v$upstream (UPSTREAM_VERSION)"
[ "$res_version" = "$upstream" ] || die "components/iterm2-resources/version VERSION $res_version is not $upstream (UPSTREAM_VERSION)"

. "$REPO_ROOT/build/msc.sh"
MODULES=$(dirname "$SHIPYARD_SCRIPTS")
for m in MavericksSDKMetadata MavericksXcodeInputs MavericksResourceInputs MavericksHostTools; do
  [ -f "$MODULES/$m.cmake" ] || die "shipyard at $MODULES has no $m.cmake: install a shipyard release that provides it"
done

installed() {
  _m="$ROOT/usr/local/mavergreen/$1/mavergreen.plist"
  [ -f "$_m" ] || die "$1 is pinned at $2 but not installed (no $_m)"
  _iv=$(plutil -extract version xml1 -o - "$_m" 2>/dev/null | sed -n 's:.*<string>\(.*\)</string>.*:\1:p')
  [ "$_iv" = "$2" ] || die "$1 is pinned at $2 but ${_iv:-an unreadable version} is installed ($_m)"
}
mode=$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")
case "$mode" in
  native) clang_short=clang22 ;;
  cross) clang_short=clang22-cross ;;
  *) die "mavericks_mode.sh answered '$mode'" ;;
esac
installed "$clang_short" "$clang_pin"
compiler="$ROOT/usr/local/mavergreen/$clang_short/bin/clang"
[ -x "$compiler" ] || die "$clang_short $clang_pin has no executable $compiler"
installed recaulk "$recaulk_pin"
recipes="$ROOT/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json"
[ -f "$recipes" ] || die "recaulk $recaulk_pin has no $recipes"
# platform: Recaulk 20261107.2 installed share/sdk-metadata 0700 root; say so rather than "has no"
[ -r "$recipes" ] || die "recaulk $recaulk_pin's $recipes is not readable by $(id -un): reinstall a release that installs it world-readable"
deps="$REPO_ROOT/components/dependencies.tsv"
[ -f "$deps" ] || die "components/dependencies.tsv is missing"

sh "$SHIPYARD_SCRIPTS/fetch_pinned_source.sh" "$src_repo" "$src_digest" "$src_sha" "$OUT/source" \
  || die "the pinned source did not fetch and verify"
[ "$(cat "$OUT/source/.mavergreen-source")" = "$src_repo $src_digest $src_sha" ] \
  || die "the fetched source's stamp is not the pin"
sh "$SHIPYARD_SCRIPTS/apply_patches.sh" "$OUT/source" "$REPO_ROOT/patches" || die "a patch does not apply"

. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"
mkdir -p "$CACHE"
zip_name="iTerm2-resources-$res_version-$res_sha.zip"
shipyard_fetch_verified "$res_url" "$res_sha" "$CACHE" "$zip_name" || die "the resource ZIP did not fetch and verify"
zip="$CACHE/$zip_name"

for p in "$OUT" "$zip" "$recipes" "$compiler" "$deps"; do
  case "$p" in *']==]'*|*'
'*) die "a path cannot be written into inputs.cmake: $p" ;; esac
done
j() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }
patches_json=
for p in "$REPO_ROOT"/patches/*.patch; do
  [ -f "$p" ] || continue
  patches_json="$patches_json${patches_json:+, }{\"name\": \"$(j "$(basename "$p")")\", \"sha256\": \"$(shasum -a 256 "$p" | cut -d' ' -f1)\"}"
done
{
  echo "# Generated by build/prepare-inputs.sh from the pins of $REPO_ROOT; do not edit."
  echo "set(ITERM_UPSTREAM_VERSION [==[$upstream]==])"
  echo "set(ITERM_SOURCE_DIR [==[$OUT/source]==])"
  echo "set(ITERM_RESOURCES_ZIP [==[$zip]==])"
  echo "set(ITERM_RESOURCES_SHA256 [==[$res_sha]==])"
  echo "set(ITERM_RECAULK_RECIPES [==[$recipes]==])"
  echo "set(ITERM_CLANG22_COMPILER [==[$compiler]==])"
  echo "set(ITERM_CLANG22_VERSION [==[$clang_pin]==])"
  echo "set(ITERM_DEPENDENCY_MANIFEST [==[$deps]==])"
  echo "set(ITERM_MODE [==[$mode]==])"
} > "$OUT/inputs.cmake.tmp"
cat > "$OUT/inputs.json.tmp" <<EOF
{
  "schema": 1,
  "upstream_version": "$(j "$upstream")",
  "mode": "$(j "$mode")",
  "source": {"repo": "$(j "$src_repo")", "ref": "$(j "$src_ref")", "digest": "$(j "$src_digest")", "sha256": "$(j "$src_sha")", "dir": "$(j "$OUT/source")"},
  "resources": {"url": "$(j "$res_url")", "sha256": "$(j "$res_sha")", "version": "$(j "$res_version")", "zip": "$(j "$zip")"},
  "clang22": {"product": "$(j "$clang_short")", "version": "$(j "$clang_pin")", "compiler": "$(j "$compiler")"},
  "recaulk": {"version": "$(j "$recaulk_pin")", "recipes": "$(j "$recipes")"},
  "dependencies": "$(j "$deps")",
  "patches": [$patches_json]
}
EOF
mv "$OUT/inputs.json.tmp" "$OUT/inputs.json"
mv "$OUT/inputs.cmake.tmp" "$OUT/inputs.cmake"
echo "prepare-inputs: $OUT/inputs.cmake"
