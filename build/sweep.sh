#!/bin/sh
# platform: macOS-only -- runs the configured clang22 commands of a macOS build.
#   usage: sweep.sh BUILD_DIR OUT_DIR
#          Syntax-checks every unit in BUILD_DIR/compile_commands.json (-fsyntax-only, every error kept),
#          in parallel, and writes OUT_DIR/units/<index>.log, OUT_DIR/errors.tsv (unit, file, line,
#          message: one row per error) and OUT_DIR/summary.txt (units, failed, errors). Exit 0 when no
#          unit has an error, 1 otherwise, 2 on a usage error or a shard that failed. OUT_DIR is replaced.
# spec: BUILD.md "Build evidence" -- a normal build stops at the first failed target and skips everything
#       that depends on it; the sweep measures all of it, as a diagnostic, never as the build's verdict.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
[ "$#" -eq 2 ] || { echo 'usage: sweep.sh BUILD_DIR OUT_DIR' >&2; exit 2; }
B=$1; OUT=$2
[ -f "$B/compile_commands.json" ] || { echo "sweep: no $B/compile_commands.json (configure with CMAKE_EXPORT_COMPILE_COMMANDS ON)" >&2; exit 2; }
CMAKE=$(sed -n 's/^CMAKE_COMMAND:INTERNAL=//p' "$B/CMakeCache.txt")
abs() { if [ -d "$1" ]; then (CDPATH= cd "$1" && pwd -P); else echo "$(CDPATH= cd "$(dirname "$1")" 2>/dev/null && pwd -P)/$(basename "$1")"; fi; }
# platform: OUT_DIR is replaced, so an OUT_DIR that is the build directory or holds it would delete the build
case "$(abs "$B")/" in "$(abs "$OUT")/"*) echo "sweep: OUT_DIR $OUT is or holds the build directory $B" >&2; exit 2 ;; esac
rm -rf "$OUT"; mkdir -p "$OUT/units"
n=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
i=0; pids=""
while [ "$i" -lt "$n" ]; do
  "$CMAKE" -DCOMMANDS="$B/compile_commands.json" -DOUT="$OUT" -DSHARD="$i" -DSHARDS="$n" \
    -P "$REPO_ROOT/build/sweep.cmake" > "$OUT/shard-$i.log" 2>&1 &
  pids="$pids $!"
  i=$((i + 1))
done
# platform: a shard that cannot read its units writes no logs, which would read as a clean sweep
broken=0
for p in $pids; do wait "$p" || broken=1; done
if [ "$broken" -ne 0 ]; then
  cat "$OUT"/shard-*.log >&2
  echo "sweep: a shard failed; the sweep measured nothing reliable" >&2
  exit 2
fi
TAB=$(printf '\t')
printf 'unit\tfile\tline\tmessage\n' > "$OUT/errors.tsv"
units=0; failed=0
for log in "$OUT"/units/*.log; do
  [ -f "$log" ] || continue
  units=$((units + 1))
  unit=$(basename "$log" .log)
  [ "$(sed -n 's/^rc //p' "$log")" = 0 ] || failed=$((failed + 1))
  # spec: BUILD.md "Build evidence" -- every error counts, located (file:line:col) or not ("fatal error:" for
  #       a missing header, "clang: error:" for a bad argument, recorded with file - and line 0)
  awk -v u="$unit" -v OFS="$TAB" '
    match($0, /:[0-9]+:[0-9]+: (fatal )?error: /) {
      split(substr($0, RSTART + 1, RLENGTH), q, ":")
      print u, substr($0, 1, RSTART - 1), q[1], substr($0, RSTART + RLENGTH); next }
    /^[^:]+: (fatal )?error: / { m = $0; sub(/^[^:]+: (fatal )?error: /, "", m); print u, "-", 0, m }' "$log" >> "$OUT/errors.tsv"
done
errors=$(($(wc -l < "$OUT/errors.tsv") - 1))
printf 'units %s\nfailed %s\nerrors %s\n' "$units" "$failed" "$errors" > "$OUT/summary.txt"
cat "$OUT/summary.txt"
[ "$failed" -eq 0 ] && [ "$errors" -eq 0 ]
