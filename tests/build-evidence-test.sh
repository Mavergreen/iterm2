#!/bin/sh
# platform: macOS-only -- builds CMake fixtures with clang22 and runs shipyard's Mach-O compat guard.
# spec: BUILD.md "Build evidence" -- build/record-build.sh BUILD_DIR EVIDENCE_DIR [TARGET [OUTPUT]] builds one target,
#       keeps the whole log and the real exit status, and writes findings.json: PASS only for a
#       complete build whose expected output exists and whose Mach-O files pass the compat guard;
#       BLOCKED otherwise, with the build's own nonzero status. Runtime is never measured here, so it
#       is always UNMEASURED; nothing is copied out of the build as a promoted artifact.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-evidence-test.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
T=$(CDPATH= cd "$T" && pwd -P)
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
CMAKE=${SHIPYARD_CMAKE:-/usr/local/mavergreen/bin/shipyard-cmake}
for c in /usr/local/mavergreen/clang22/bin/clang /usr/local/mavergreen/clang22-cross/bin/clang; do
  [ -x "$c" ] && CLANG22=$c && break
done
[ -n "${CLANG22:-}" ] || { echo "build-evidence-test: no clang22" >&2; exit 1; }

# spec: BUILD.md "Inputs" -- a fixture selects its compiler as cmake/ITermInputs.cmake does: with a plain
#       set() before project(), so it is never in CMakeCache.txt
project() { # NAME BODY -- a fixture project whose target iTerm2-app is BODY
  mkdir -p "$T/$1"
  printf 'cmake_minimum_required(VERSION 3.25)\nset(CMAKE_C_COMPILER "%s")\nproject(fixture LANGUAGES C)\n%s\n' "$CLANG22" "$2" > "$T/$1/CMakeLists.txt"
  "$CMAKE" -S "$T/$1" -B "$T/$1/b" >"$T/$1.configure" 2>&1 \
    || { cat "$T/$1.configure" >&2; fail "$1: the fixture did not configure"; }
}
record() { # NAME -- run the recorder; its exit status is $rc
  rc=0; sh "$REPO_ROOT/build/record-build.sh" "$T/$1/b" "$T/$1-evidence" >"$T/$1.out" 2>&1 || rc=$?
}
field() { # NAME KEY -- a top-level string or number field of findings.json
  sed -n "s/^  \"$2\": \"*\([^\",]*\)\"*,*\$/\1/p" "$T/$1-evidence/findings.json"
}

printf 'int main(void) { return undeclared_symbol; }\n' > "$T/broken.c"
project broken "add_executable(iTerm2 \"$T/broken.c\")
add_custom_target(iTerm2-app ALL DEPENDS iTerm2)"
record broken
[ "$rc" -ne 0 ] || fail "broken: the recorder exited 0 for a failed build"
[ "$(field broken build_status)" = BLOCKED ] || fail "broken: build_status is not BLOCKED"
[ "$(field broken build_exit)" = "$rc" ] && [ "$rc" -ne 0 ] || fail "broken: build_exit is not the recorder's nonzero status"
grep -q 'undeclared_symbol' "$T/broken-evidence/build.log" || fail "broken: the diagnostic is not in build.log"
[ "$(field broken runtime)" = UNMEASURED ] || fail "broken: runtime is not UNMEASURED"
[ "$(field broken compat)" != PASS ] || fail "broken: compat claims PASS without a build"
[ -z "$(find "$T/broken-evidence" -name '*.app' -o -type f -perm -u+x | head -1)" ] || fail "broken: an artifact was promoted"

printf 'int main(void) { return 0; }\n' > "$T/ok.c"
project ok "add_executable(iTerm2 \"$T/ok.c\")
add_custom_target(iTerm2-app ALL
  COMMAND \"\${CMAKE_COMMAND}\" -E make_directory \"\${CMAKE_BINARY_DIR}/iTerm2.app/Contents/MacOS\"
  COMMAND \"\${CMAKE_COMMAND}\" -E copy \"\$<TARGET_FILE:iTerm2>\" \"\${CMAKE_BINARY_DIR}/iTerm2.app/Contents/MacOS/iTerm2\"
  DEPENDS iTerm2)"
record ok
[ "$rc" -eq 0 ] || { cat "$T/ok.out" >&2; fail "ok: the recorder exited $rc for a good build"; }
[ "$(field ok build_status)" = PASS ] || fail "ok: build_status is not PASS"
[ "$(field ok compat)" = PASS ] || fail "ok: compat is not PASS"
[ "$(field ok runtime)" = UNMEASURED ] || fail "ok: runtime is not UNMEASURED"
grep -q '"Contents/MacOS/iTerm2"' "$T/ok-evidence/findings.json" || fail "ok: the output inventory does not list the executable"
grep -q '"host":' "$T/ok-evidence/findings.json" && grep -q '"mode":' "$T/ok-evidence/findings.json" \
  || fail "ok: findings.json lacks host or mode"
[ "$(field ok compiler)" = "$CLANG22" ] || fail "ok: findings.json does not name the compiler that built it"
[ "$(field ok compiler_version)" = "$("$CLANG22" --version | head -1)" ] || fail "ok: findings.json does not record the compiler's version"
grep -q '"shipyard": {"version": "[0-9][0-9.]*", "modules": "/' "$T/ok-evidence/findings.json" \
  || fail "ok: findings.json does not record shipyard's version and modules"

# platform: another host takes committed state as an archive extract, not a git work tree; its state is
#           measured from its files' contents, so a clean build PASSes and one that writes into it does not
mkdir -p "$T/archive"; cp -R "$REPO_ROOT/build" "$T/archive/build"
rc=0; sh "$T/archive/build/record-build.sh" "$T/ok/b" "$T/archive-evidence" >"$T/archive.out" 2>&1 || rc=$?
before=$(sed -n 's/^  "checkout_before": "\(.*\)",$/\1/p' "$T/archive-evidence/findings.json")
case "$before" in
  ''|UNMEASURED|e3b0c44298fc1c14) fail "archive: checkout_before is not a measurement of the archive's files ($before)" ;;
esac
[ "$rc" -eq 0 ] && [ "$(sed -n 's/^  "build_status": "\(.*\)",$/\1/p' "$T/archive-evidence/findings.json")" = PASS ] \
  || fail "archive: a clean build of an archive extract is not a PASS"
project dirty "add_custom_target(iTerm2-app ALL
  COMMAND \"\${CMAKE_COMMAND}\" -E touch \"$T/archive/build/stray\"
  COMMAND \"\${CMAKE_COMMAND}\" -E make_directory \"\${CMAKE_BINARY_DIR}/iTerm2.app/Contents/MacOS\"
  COMMAND \"\${CMAKE_COMMAND}\" -E copy \"$T/ok/b/iTerm2\" \"\${CMAKE_BINARY_DIR}/iTerm2.app/Contents/MacOS/iTerm2\")"
rc=0; sh "$T/archive/build/record-build.sh" "$T/dirty/b" "$T/dirty-evidence" >"$T/dirty.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && [ "$(field dirty build_status)" = BLOCKED ] && grep -q 'changed the checkout' "$T/dirty-evidence/findings.json" \
  || fail "dirty: a build that wrote into the archive checkout was not BLOCKED"

# spec: BUILD.md "Build evidence" -- a leg that was not run is ABSENT, with its reason, and never a build
rc=0; sh "$REPO_ROOT/build/record-build.sh" --absent "$T/absent-evidence" "no authorized Apple Silicon host" >"$T/absent.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "absent: the recorder exited 0 for an absent leg"
[ "$(field absent build_status)" = ABSENT ] || fail "absent: build_status is not ABSENT"
grep -q 'no authorized Apple Silicon host' "$T/absent-evidence/findings.json" || fail "absent: the reason is not recorded"
[ "$(field absent compat)" = UNMEASURED ] && [ "$(field absent runtime)" = UNMEASURED ] || fail "absent: claims a measurement"
[ ! -e "$T/absent-evidence/build.log" ] || fail "absent: a build log exists for a leg that did not run"

project empty "add_custom_target(iTerm2-app ALL COMMAND \"\${CMAKE_COMMAND}\" -E true)"
mkdir -p "$T/empty/b/iTerm2.app/Contents/MacOS"; cp "$T/ok/b/iTerm2" "$T/empty/b/iTerm2.app/Contents/MacOS/iTerm2"
record empty
grep -q '"Contents/MacOS/iTerm2"' "$T/empty-evidence/findings.json" && fail "empty: a stale iTerm2.app from an earlier run was inventoried"
[ "$rc" -ne 0 ] || fail "empty: the recorder exited 0 with no iTerm2.app"
[ "$(field empty build_status)" = BLOCKED ] || fail "empty: build_status is not BLOCKED"

[ "$fails" -eq 0 ] || { echo "build-evidence-test: $fails failure(s)" >&2; exit 1; }
echo "build-evidence-test: OK"
