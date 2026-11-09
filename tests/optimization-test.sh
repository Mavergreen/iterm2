#!/bin/sh
# platform: macOS-only -- reads the native build's compile commands, which only a Mac's build writes
# spec: BUILD.md "Targets" -- everything this product compiles carries an optimization level (clang's own
#       default is -O0); the one exception is the updater's main, which shipyard's mavericks_add_updater_app
#       compiles, and which is shipyard's to set
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
B=${ITERM_BUILD_DIR:-${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/$(basename "$REPO_ROOT")-native}
CC=$B/compile_commands.json
[ -f "$CC" ] || { echo "optimization-test: no compile commands at $CC; skipping"; exit 77; }
# platform: compile_commands.json writes one "file" per entry after its "command"
missing=$(awk '
  /"command":/ { opt = ($0 ~ /[[:space:]]-O[0123sz][[:space:]]/) }
  /"file":/ { f = $0; sub(/.*"file": *"/, "", f); sub(/".*/, "", f); if (!opt) print f }' "$CC" |
  grep -v '/iterm2-updater-main\.m$' || :)
[ -z "$missing" ] || { printf 'FAIL: compiled with no optimization level:\n%s\n' "$missing" >&2; echo "optimization-test: failed" >&2; exit 1; }
echo "optimization-test: OK"
