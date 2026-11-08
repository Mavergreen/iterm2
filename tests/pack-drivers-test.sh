#!/bin/sh
# platform: macOS-only -- reads the native build's drivers with clang22's llvm-otool
# spec: BUILD.md "Acceptance on 10.9" -- the packed drivers run in the 10.9 guest, where the build directory
#       does not exist, so every @rpath library a driver loads resolves inside the pack, beside it
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
B=${ITERM_BUILD_DIR:-${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/$(basename "$REPO_ROOT")-native}
ls "$B"/tests/drivers/driver-* > /dev/null 2>&1 || { echo "pack-drivers-test: no drivers built in $B; skipping"; exit 77; }
OTOOL=
for d in /usr/local/mavergreen/clang22/bin /usr/local/mavergreen/clang22-cross/bin; do
  [ -x "$d/llvm-otool" ] && OTOOL=$d/llvm-otool && break
done
[ -n "$OTOOL" ] || { echo "pack-drivers-test: SKIP: no clang22 llvm-otool"; exit 77; }
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-pack-drivers-test.XXXXXX")   # platform: 10.9 BSD mktemp requires a template
trap 'rm -rf "$T"' EXIT
sh "$REPO_ROOT/build/pack-drivers.sh" "$B" "$T/drivers.tar" > /dev/null || { fail "pack-drivers.sh failed"; exit 1; }
mkdir "$T/p"; tar -xf "$T/drivers.tar" -C "$T/p"
for drv in "$T"/p/driver-*; do
  n=$(basename "$drv")
  rpaths=$("$OTOOL" -l "$drv" | awk '$1 == "cmd" { c = $2 } c == "LC_RPATH" && $1 == "path" { print $2 }')
  "$OTOOL" -L "$drv" | sed -n 's|^[[:space:]]*@rpath/\([^ ]*\) (.*|\1|p' | while read -r lib; do
    found=no
    for r in $rpaths; do
      # platform: dyld expands @executable_path only followed by a slash; a bare one stays literal
      case "$r" in @executable_path/*) [ -e "$T/p/${r#@executable_path/}/$lib" ] && found=yes ;; esac
    done
    [ "$found" = yes ] || echo "$n loads @rpath/$lib, which no @executable_path rpath finds in the pack"
  done
done > "$T/missing"
[ ! -s "$T/missing" ] || { cat "$T/missing" >&2; fail "a packed driver loads a library from outside the pack"; }
[ "$fails" -eq 0 ] || { echo "pack-drivers-test: $fails failure(s)" >&2; exit 1; }
echo "pack-drivers-test: OK"
