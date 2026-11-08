#!/bin/sh
# platform: macOS-only -- reads the host with sw_vers and runs shipyard's Mach-O compat guard.
#   usage: record-build.sh BUILD_DIR EVIDENCE_DIR [TARGET [OUTPUT]]
#          record-build.sh --absent EVIDENCE_DIR REASON
#          Builds TARGET (default iTerm2-app) in the configured BUILD_DIR, keeping the whole log in
#          EVIDENCE_DIR/build.log and the build's real exit status, and writes EVIDENCE_DIR/findings.json
#          (schema 1): build_status PASS or BLOCKED, build_exit, host, mode, the declared inputs
#          (inputs.json, when the build names one), the checkout's state before and after (git's view of
#          a work tree; a hash of every file's contents otherwise), the compiler CMake detected and its
#          version, shipyard's version and module directory, an inventory
#          of OUTPUT (default iTerm2.app, under BUILD_DIR), the compat guard's verdict over every Mach-O
#          in it (compat PASS, FAIL or UNMEASURED) and runtime, which this never measures: UNMEASURED.
#          An OUTPUT left by an earlier run is removed before building.
#          A build configured with ITERM_UNRELEASED_RECIPES is BLOCKED, naming them, however it builds.
#          PASS needs a zero exit, OUTPUT present, compat PASS and the checkout unchanged by the build.
#          Exit 0 on PASS; otherwise the build's own nonzero status, or 1. Nothing is copied out of
#          the build: the evidence is a record, not an artifact.
#          --absent records a leg that was not run (no authorized host, say): build_status ABSENT with
#          REASON, nothing measured, no build log; exit 3.
# spec: BUILD.md "Build evidence".
set -u
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
if [ "${1:-}" = --absent ]; then
  [ "$#" -eq 3 ] || { echo 'usage: record-build.sh --absent EVIDENCE_DIR REASON' >&2; exit 2; }
  mkdir -p "$2" || exit 1
  cat > "$2/findings.json" <<EOF2
{
  "schema": 1,
  "build_status": "ABSENT",
  "build_exit": null,
  "reasons": "$(printf '%s' "$3" | sed 's/["\\]/\\&/g')",
  "recorded": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "compat": "UNMEASURED",
  "runtime": "UNMEASURED",
  "inventory": []
}
EOF2
  echo "record-build: ABSENT ($2/findings.json): $3"
  exit 3
fi
[ "$#" -ge 2 ] && [ "$#" -le 4 ] || { echo 'usage: record-build.sh BUILD_DIR EVIDENCE_DIR [TARGET [OUTPUT]]' >&2; exit 2; }
B=$1; E=$2; TARGET=${3:-iTerm2-app}; OUTPUT=${4:-iTerm2.app}
[ -f "$B/CMakeCache.txt" ] || { echo "record-build: $B is not a configured build directory" >&2; exit 2; }
mkdir -p "$E" || exit 1
. "$REPO_ROOT/build/msc.sh" || exit 1
CMAKE=$(sed -n 's/^CMAKE_COMMAND:INTERNAL=//p' "$B/CMakeCache.txt")
cache() { sed -n "s/^$1:[A-Z]*=//p" "$B/CMakeCache.txt" | head -1; }
# platform: an archive extract (how another host takes committed state) is not a git work tree, so its
#           state is a hash of every file's path and contents; a work tree's is git's own view
tree_state() {
  if (cd "$REPO_ROOT" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    (cd "$REPO_ROOT" && git status --porcelain | sort | shasum -a 256 | cut -c1-16)
  else
    (cd "$REPO_ROOT" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
       printf '%s %s\n' "$(shasum -a 256 < "$f" | cut -d' ' -f1)" "$f"
     done | shasum -a 256 | cut -c1-16)
  fi
}
# platform: cmake/ITermInputs.cmake selects the compiler with a plain set() before project(), so it is not
#           in CMakeCache.txt; CMake records the one it detected in CMakeFiles/<version>/CMakeCCompiler.cmake
compiler=$(sed -n 's/^set(CMAKE_C_COMPILER "\(.*\)")$/\1/p' "$B"/CMakeFiles/*/CMakeCCompiler.cmake 2>/dev/null | head -1)

compiler_version=$("${compiler:-/nonexistent/cc}" --version 2>/dev/null | head -1)
shipyard_modules=$(dirname "$SHIPYARD_SCRIPTS")
shipyard_version=$(plutil -extract version xml1 -o - "$shipyard_modules/../../../mavergreen.plist" 2>/dev/null \
  | sed -n 's:.*<string>\(.*\)</string>.*:\1:p')
j() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }
# spec: BUILD.md "Build evidence" -- the inventory is of this build's output: one left by an earlier run is removed first
rm -rf "$B/$OUTPUT"

before=$(tree_state)
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
"$CMAKE" --build "$B" --target "$TARGET" >"$E/build.log" 2>&1
build_exit=$?
after=$(tree_state)

status=PASS; reasons=""
blocked() { status=BLOCKED; reasons="$reasons${reasons:+; }$1"; }
[ "$build_exit" -eq 0 ] || blocked "the build exited $build_exit (build.log)"
out="$B/$OUTPUT"
inventory=""
compat=UNMEASURED
if [ "$build_exit" -eq 0 ] && [ ! -e "$out" ]; then
  blocked "the build exited 0 but produced no $OUTPUT"
fi
if [ -e "$out" ]; then
  inventory=$(cd "$out" && find . -type f | sort | while IFS= read -r f; do
    printf '    {"path": "%s", "sha256": "%s"},\n' "$(j "${f#./}")" "$(shasum -a 256 "$f" | cut -d' ' -f1)"
  done | sed '$ s/,$//')
  machos=$(cd "$out" && find . -type f | while IFS= read -r f; do
    case "$(file -b "$f")" in (*Mach-O*) echo "$out/${f#./}" ;; esac
  done)
  if [ -n "$machos" ]; then
    otool_dir=$(dirname "${compiler:-/nonexistent/cc}")
    for t in llvm-otool:OTOOL llvm-nm:NM llvm-lipo:LIPO llvm-strings:STRINGS; do
      [ -x "$otool_dir/${t%%:*}" ] && export "${t#*:}=$otool_dir/${t%%:*}"
    done
    # shellcheck disable=SC2086
    if MAVERICKS_DEVIATIONS_ROOT="$REPO_ROOT" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" $machos >"$E/compat.log" 2>&1; then
      compat=PASS
    else
      compat=FAIL; blocked "the compat guard refused a Mach-O (compat.log)"
    fi
  else
    blocked "$OUTPUT holds no Mach-O to check"
  fi
fi
[ "$compat" = PASS ] || [ "$status" = BLOCKED ] || blocked "compat is $compat"
[ "$before" = "$after" ] || blocked "the build changed the checkout"
# spec: BUILD.md "Build evidence" -- driver tests (CTest label "driver") run after a native build that
#       passed so far; a cross build's x86_64 10.9 drivers cannot run on its host, so it records them
#       UNMEASURED, never PASS or FAIL; so does a build that did not pass, as its drivers never ran
drivers=NONE; drivers_reason=""
CTEST=$(cache CMAKE_CTEST_COMMAND)
if [ -n "$CTEST" ] && "$CTEST" --test-dir "$B" -N -L driver 2>/dev/null | grep -q 'Test *#'; then
  if [ "$status" != PASS ]; then
    drivers=UNMEASURED; drivers_reason="the build did not pass, so its drivers did not run"
  elif [ "$(cache MAVERICKS_EXPECTED_MODE)" = cross ]; then
    drivers=UNMEASURED; drivers_reason="cross build: x86_64 10.9 drivers do not run here"
  elif "$CMAKE" --build "$B" --target drivers >>"$E/build.log" 2>&1 \
       && "$CTEST" --test-dir "$B" -L driver --output-on-failure >>"$E/build.log" 2>&1; then
    drivers=PASS
  else
    drivers=FAIL; blocked "drivers failed (build.log)"
  fi
fi
unreleased=$(cache ITERM_UNRELEASED_RECIPES)
[ "$(cache ITERM_UNRELEASED_INPUTS)" != ON ] || blocked "unreleased recipes: ${unreleased:-unnamed}"

inputs_file=$(cache ITERM_INPUTS_FILE)
inputs="null"
if [ -n "$inputs_file" ] && [ -f "$(dirname "$inputs_file")/inputs.json" ]; then
  inputs=$(sed 's/^/  /' "$(dirname "$inputs_file")/inputs.json" | sed '1s/^  //')
fi
cat > "$E/findings.json" <<EOF
{
  "schema": 1,
  "build_status": "$status",
  "build_exit": $build_exit,
  "reasons": "$(j "$reasons")",
  "started": "$started",
  "host": {"os": "$(j "$(sw_vers -productVersion 2>/dev/null)")", "arch": "$(j "$(uname -m)")", "name": "$(j "$(uname -n)")"},
  "mode": "$(j "$(cache MAVERICKS_EXPECTED_MODE)")",
  "compiler": "$(j "$compiler")",
  "compiler_version": "$(j "$compiler_version")",
  "shipyard": {"version": "$(j "$shipyard_version")", "modules": "$(j "$shipyard_modules")"},
  "sdk": "$(j "$(cache CMAKE_OSX_SYSROOT)")",
  "target": "$(j "$TARGET")",
  "checkout_before": "$before",
  "checkout_after": "$after",
  "compat": "$compat",
  "drivers": "$drivers",
  "drivers_reason": "$(j "$drivers_reason")",
  "unreleased_recipes": "$(j "${unreleased:-}")",
  "runtime": "UNMEASURED",
  "inputs": $inputs,
  "output": "$(j "$OUTPUT")",
  "inventory": [
$inventory
  ]
}
EOF
echo "record-build: $status ($E/findings.json)${reasons:+: $reasons}"
[ "$status" = PASS ] && exit 0
[ "$build_exit" -ne 0 ] && exit "$build_exit"
exit 1
