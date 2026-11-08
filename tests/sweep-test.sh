#!/bin/sh
# platform: macOS-only -- compiles CMake fixtures with clang22.
# spec: BUILD.md "Build evidence" -- build/sweep.sh syntax-checks every unit of compile_commands.json, so
#       a unit whose target depends on a failed target is still measured; it writes errors.tsv and
#       summary.txt and exits 0 only when no unit has an error.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-sweep-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
T=$(CDPATH= cd "$T" && pwd -P)
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
CMAKE=${SHIPYARD_CMAKE:-/usr/local/mavergreen/bin/shipyard-cmake}
[ -x "$CMAKE" ] || { echo "sweep-test: SKIP: no shipyard-cmake at $CMAKE (the 10.9 acceptance guest has none)"; exit 77; }
for c in /usr/local/mavergreen/clang22/bin/clang /usr/local/mavergreen/clang22-cross/bin/clang; do
  [ -x "$c" ] && CLANG22=$c && break
done
[ -n "${CLANG22:-}" ] || { echo "sweep-test: SKIP: no clang22 installed (the 10.9 acceptance guest has none)"; exit 77; }

fixture() { # NAME A-BODY B-BODY -- target b links target a
  mkdir -p "$T/$1"
  printf '%s\n' "$2" > "$T/$1/a.c"; printf '%s\n' "$3" > "$T/$1/b.c"
  printf 'cmake_minimum_required(VERSION 3.25)\nset(CMAKE_C_COMPILER "%s")\nproject(f LANGUAGES C)\nset(CMAKE_EXPORT_COMPILE_COMMANDS ON)\nadd_library(a STATIC a.c)\nadd_executable(b b.c)\ntarget_link_libraries(b PRIVATE a)\n' "$CLANG22" > "$T/$1/CMakeLists.txt"
  # platform: CMake defaults to the host's arch, arm64 on Apple Silicon, which the 10.9 SDK lacks; name x86_64
  "$CMAKE" -S "$T/$1" -B "$T/$1/b" -DCMAKE_OSX_ARCHITECTURES=x86_64 >"$T/$1.configure" 2>&1 || fail "$1: the fixture did not configure"
}
sum() { sed -n "s/^$2 //p" "$T/$1-out/summary.txt"; }

fixture broken 'int a(void) { return missing_in_a; }' 'int a(void); int main(void) { return missing_in_b + a(); }'
rc=0; sh "$REPO_ROOT/build/sweep.sh" "$T/broken/b" "$T/broken-out" >"$T/broken.log" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "broken: exit $rc, not 1"
[ "$(sum broken units)" = 2 ] && [ "$(sum broken failed)" = 2 ] && [ "$(sum broken errors)" = 2 ] \
  || fail "broken: summary is not units 2, failed 2, errors 2: $(tr '\n' ' ' < "$T/broken-out/summary.txt" 2>/dev/null)"
grep -q "missing_in_a" "$T/broken-out/errors.tsv" && grep -q "missing_in_b" "$T/broken-out/errors.tsv" \
  || fail "broken: errors.tsv lacks an error from each target"
awk -F'\t' 'NR > 1 && (NF != 4 || $3 !~ /^[0-9]+$/)' "$T/broken-out/errors.tsv" | grep -q . && fail "broken: a malformed errors.tsv row"
[ "$(head -1 "$T/broken-out/errors.tsv")" = "$(printf 'unit\tfile\tline\tmessage')" ] || fail "broken: errors.tsv header"
[ ! -e "$T/broken/b/CMakeFiles/a.dir/a.c.o" ] || fail "broken: the sweep wrote an object file"

fixture clean 'int a(void) { return 0; }' 'int a(void); int main(void) { return a(); }'
rc=0; sh "$REPO_ROOT/build/sweep.sh" "$T/clean/b" "$T/clean-out" >"$T/clean.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && [ "$(sum clean errors)" = 0 ] && [ "$(sum clean units)" = 2 ] || fail "clean: exit $rc or a nonzero error count"

fixture fatal '#include "no_such_header.h"' 'int main(void) { return 0; }'
rc=0; sh "$REPO_ROOT/build/sweep.sh" "$T/fatal/b" "$T/fatal-out" >"$T/fatal.log" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && [ "$(sum fatal failed)" = 1 ] && [ "$(sum fatal errors)" = 1 ] \
  || fail "fatal: a missing header is not counted: exit $rc, $(tr '\n' ' ' < "$T/fatal-out/summary.txt" 2>/dev/null)"
grep -q "no_such_header.h" "$T/fatal-out/errors.tsv" || fail "fatal: errors.tsv lacks the fatal error"

mkdir -p "$T/flag/b"; cp "$T/clean/b/CMakeCache.txt" "$T/flag/b/"
sed 's/ -c / -c -mavergreen-no-such-flag /' "$T/clean/b/compile_commands.json" > "$T/flag/b/compile_commands.json"
rc=0; sh "$REPO_ROOT/build/sweep.sh" "$T/flag/b" "$T/flag-out" >"$T/flag.log" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && [ "$(sum flag failed)" = 2 ] && [ "$(sum flag errors)" = 2 ] \
  || fail "flag: an error with no file location is not counted: exit $rc, $(tr '\n' ' ' < "$T/flag-out/summary.txt" 2>/dev/null)"
awk -F'\t' 'NR > 1 && (NF != 4 || $3 !~ /^[0-9]+$/)' "$T/flag-out/errors.tsv" | grep -q . && fail "flag: a malformed errors.tsv row"

for out in "$T/clean/b" "$T/clean"; do
  rc=0; sh "$REPO_ROOT/build/sweep.sh" "$T/clean/b" "$out" >"$T/same.log" 2>&1 || rc=$?
  [ "$rc" -eq 2 ] && [ -f "$T/clean/b/CMakeCache.txt" ] || fail "an OUT_DIR of $out (the build dir or above it) was not refused"
done

printf '[{"directory": "/", "file": "/x.c", "arguments": ["cc", "-c", "/x.c"]}]' > "$T/arguments.json"
mkdir -p "$T/arg/b"; cp "$T/clean/b/CMakeCache.txt" "$T/arg/b/"; cp "$T/arguments.json" "$T/arg/b/compile_commands.json"
rc=0; sh "$REPO_ROOT/build/sweep.sh" "$T/arg/b" "$T/arg-out" >"$T/arg.log" 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "a sweep whose shard could not read its units exited $rc, not 2"

[ "$fails" -eq 0 ] || { echo "sweep-test: $fails failure(s)" >&2; exit 1; }
echo "sweep-test: OK"
