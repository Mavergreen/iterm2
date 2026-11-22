#!/bin/sh
# platform: macOS-only -- configures the census with shipyard's native (10.9) or cross (modern Mac) preset.
#   usage: census.sh INPUTS_ROOT SETTINGS_FILE OUT_DIR
#          Compiles every source of the targets SETTINGS_FILE names (see cmake/ITermCensus.cmake) from the
#          inputs build/prepare-inputs.sh wrote to INPUTS_ROOT, keeps going past failures, and writes
#          OUT_DIR/census.tsv, summary.tsv and symbols.tsv (build/census-classify.sh) beside the logs.
#          Exits 0 however many sources fail; non-zero only when the census itself could not run.
#          ITERM_CENSUS_PROJECT names the .xcodeproj in the source (default iTerm2.xcodeproj).
# spec: BUILD.md "Census"
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
die() { echo "census: $*" >&2; exit 1; }
[ "$#" -eq 3 ] || { echo 'usage: census.sh INPUTS_ROOT SETTINGS_FILE OUT_DIR' >&2; exit 2; }
for a in "$1" "$2" "$3"; do case "$a" in /*) ;; *) die "paths must be absolute: $a" ;; esac; done
[ -f "$1/inputs.cmake" ] || die "no $1/inputs.cmake: run build/prepare-inputs.sh $1"
[ -f "$2" ] || die "no settings file $2"
mkdir -p "$3"
OUT=$(CDPATH= cd "$3" && pwd -P)
# spec: BUILD.md "Census" -- OUT_DIR/build is removed before each run, so OUT_DIR is never the checkout
case "$OUT/" in "$(CDPATH= cd "$REPO_ROOT" && pwd -P)/"*) die "OUT_DIR is inside the checkout: $OUT" ;; esac
rm -f "$OUT/census.tsv" "$OUT/summary.tsv" "$OUT/symbols.tsv"
. "$REPO_ROOT/build/msc.sh"
mode=$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")
case "$mode" in native|cross) ;; *) die "mavericks_mode.sh answered '$mode'" ;; esac
CMAKE=shipyard-cmake
command -v "$CMAKE" >/dev/null 2>&1 || CMAKE=/usr/local/mavergreen/bin/shipyard-cmake
# platform: Ninja keeps each failed compile's diagnostics together under its FAILED: line, which is how
#           census-classify.sh knows which source a diagnostic belongs to.
command -v ninja >/dev/null 2>&1 || PATH=/usr/local/mavergreen/bin:$PATH
command -v ninja >/dev/null 2>&1 || die "no ninja: install the family's (it is in /usr/local/mavergreen/bin)"

rm -rf "$OUT/build"
"$CMAKE" -S "$REPO_ROOT/census" -B "$OUT/build" --preset "$mode" \
  -DITERM_INPUTS_FILE="$1/inputs.cmake" -DITERM_CENSUS_SETTINGS="$2" \
  -DITERM_CENSUS_PROJECT="${ITERM_CENSUS_PROJECT:-iTerm2.xcodeproj}" >"$OUT/configure.log" 2>&1 \
  || { tail -20 "$OUT/configure.log" >&2; die "the census did not configure (log: $OUT/configure.log)"; }
# platform: failing compiles make the build fail; census-classify.sh then refuses any source that has
#           neither an object nor a FAILED: line, so a build that stopped early cannot read as clean
"$CMAKE" --build "$OUT/build" -- -k 0 >"$OUT/build.log" 2>&1 || :
sh "$REPO_ROOT/build/census-classify.sh" "$OUT/build.log" "$OUT/build" "$OUT"
awk -F '\t' 'NR > 1 { c += $2; o += $3; e += $4 } END { printf "census: %d compiled, %d ok, %d with errors\n", c, o, e }' "$OUT/summary.tsv"
