#!/bin/sh
# platform: host-agnostic -- packs what the build directory already holds; runs nothing
#   usage: pack-drivers.sh BUILD_DIR OUT_TAR
#          Packs BUILD_DIR's driver tests for the 10.9 guest, where a cross build's x86_64 drivers can run:
#          every tests/drivers/driver-* executable, with image_decoder, its sandbox profile and the sample
#          PNG beside them, as the image-decoder driver expects. Build the drivers target first.
set -eu
[ "$#" -eq 2 ] || { echo 'usage: pack-drivers.sh BUILD_DIR OUT_TAR' >&2; exit 2; }
B=$1; OUT=$2
d=$B/tests/drivers
src=$(sed -n 's/^ITERM_SOURCE_DIR:[A-Z]*=//p' "$B/CMakeCache.txt")
[ -n "$src" ] || src=$(sed -n 's|^set(ITERM_SOURCE_DIR \[=*\[\(.*\)\]=*\])$|\1|p' "$(sed -n 's/^ITERM_INPUTS_FILE:[A-Z]*=//p' "$B/CMakeCache.txt")" 2>/dev/null)
[ -d "$d" ] || { echo "pack-drivers: $d does not exist; build the drivers target" >&2; exit 1; }
n=$(cd "$d" && ls driver-* 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -gt 0 ] || { echo "pack-drivers: no driver in $d; build the drivers target" >&2; exit 1; }
for f in image_decoder image_decoder.sb; do [ -f "$d/$f" ] || { echo "pack-drivers: no $d/$f" >&2; exit 1; }; done
[ -f "$src/images/BigArrow.png" ] || { echo "pack-drivers: no BigArrow.png under the source ${src:-(unknown)}" >&2; exit 1; }
w=$(mktemp -d "${TMPDIR:-/tmp}/pack-drivers.XXXXXX")   # platform: 10.9 BSD mktemp requires a template
trap 'rm -rf "$w"' EXIT
cp "$d"/driver-* "$d/image_decoder" "$d/image_decoder.sb" "$src/images/BigArrow.png" "$w/"
COPYFILE_DISABLE=1 tar -cf "$OUT" -C "$w" .
echo "pack-drivers: $n drivers in $OUT"
