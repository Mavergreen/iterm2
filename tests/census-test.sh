#!/bin/sh
# platform: macOS-only -- the census compiles with the installed clang22 (native) or clang22-cross against
#           the pinned 10.9 SDK.
# spec: BUILD.md "Census" -- build/census.sh compiles every source of a candidate's targets with the
#       shipping build's compiler, SDK and Recaulk metadata, keeps going past failures, and says per file
#       what failed and why, so a newer upstream's distance from Mavericks is measured, not guessed.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-census-test.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
T=$(CDPATH= cd "$T" && pwd -P)
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }

SCRIPTS=/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/scripts
[ -x /usr/local/mavergreen/bin/shipyard-cmake ] && [ -d "$SCRIPTS" ] \
  || { echo "census-test: SKIP: no installed shipyard"; exit 77; }
case "$(sh "$SCRIPTS/mavericks_mode.sh")" in
  native) CL=clang22 ;; cross) CL=clang22-cross ;; *) echo "census-test: SKIP: no mode"; exit 77 ;;
esac
COMPILER=/usr/local/mavergreen/$CL/bin/clang
RECIPES=/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json
[ -x "$COMPILER" ] && [ -r "$RECIPES" ] || { echo "census-test: SKIP: no installed $CL or Recaulk"; exit 77; }

cp -R "$REPO_ROOT/tests/fixtures/census" "$T/src"
: > "$T/resources.zip"; : > "$T/deps.tsv"
mkdir -p "$T/inputs"
cat > "$T/inputs/inputs.cmake" <<EOC
set(ITERM_UPSTREAM_VERSION [==[0.0]==])
set(ITERM_SOURCE_DIR [==[$T/src]==])
set(ITERM_RESOURCES_ZIP [==[$T/resources.zip]==])
set(ITERM_RESOURCES_SHA256 [==[0000000000000000000000000000000000000000000000000000000000000000]==])
set(ITERM_RECAULK_RECIPES [==[$RECIPES]==])
set(ITERM_CLANG22_COMPILER [==[$COMPILER]==])
set(ITERM_CLANG22_VERSION [==[$(cat "$REPO_ROOT/components/clang22/version")]==])
set(ITERM_DEPENDENCY_MANIFEST [==[$T/deps.tsv]==])
set(ITERM_MODE [==[$(sh "$SCRIPTS/mavericks_mode.sh")]==])
EOC
census() { # settings out
  ITERM_CENSUS_PROJECT=fx.xcodeproj sh "$REPO_ROOT/build/census.sh" "$T/inputs" "$1" "$2" >"$T/log" 2>&1
}
row() { # file -- census.tsv's row for a source, as status<TAB>kind<TAB>symbol
  awk -F '\t' -v f="$1" '$2 ~ ("/" f "$") { print $3 "\t" $4 "\t" $5 }' "$T/out/census.tsv"
}
TAB=$(printf '\t')

census "$T/src/settings" "$T/out" || { tail -30 "$T/log" >&2; fail "census.sh failed on the fixture"; }
if [ -f "$T/out/census.tsv" ]; then
  [ "$(row ok.m | cut -f1)" = ok ] || fail "clean_file_ok: ok.m is '$(row ok.m)'"
  [ "$(row gap.m)" = "error${TAB}no-method${TAB}currentDrawingAppearance" ] || fail "missing_api_classified: gap.m is '$(row gap.m)'"
  [ "$(row hdr.m)" = "error${TAB}missing-header${TAB}UserNotifications/UserNotifications.h" ] \
    || fail "missing_header_classified: hdr.m is '$(row hdr.m)'"
  grep -qx "App${TAB}5${TAB}1${TAB}4" "$T/out/summary.tsv" || fail "summary_counts: App is not 5 compiled, 1 ok, 4 error: $(cat "$T/out/summary.tsv")"
  grep -qx "Lib${TAB}1${TAB}1${TAB}0" "$T/out/summary.tsv" || fail "summary_counts: Lib is not 1 compiled, 1 ok"
  grep -qx "undeclared-identifier${TAB}NSAppearanceNameDarkAqua${TAB}2" "$T/out/symbols.tsv" \
    || fail "symbols_deduplicated: $(grep DarkAqua "$T/out/symbols.tsv")"
else
  fail "census.sh wrote no census.tsv"
fi

sed '/^TARGET=Lib$/s/Lib/Nope/' "$T/src/settings" > "$T/bad-target"
if census "$T/bad-target" "$T/out2"; then fail "unknown_target_refused: a target the project lacks was accepted"; fi
grep -q 'Nope' "$T/log" || fail "unknown_target_refused: the refusal does not name the target: $(tail -3 "$T/log")"

sed '/^METADATA=OFF$/d' "$T/src/settings" > "$T/no-key"
if census "$T/no-key" "$T/out3"; then fail "missing_key_refused: a block without METADATA was accepted"; fi
grep -q 'METADATA' "$T/log" || fail "missing_key_refused: the refusal does not name METADATA: $(tail -3 "$T/log")"

printf 'TARGET=App\nPREFIX=APP\nARC=$(touch %s/pwned)\n' "$T" > "$T/shell"
census "$T/shell" "$T/out4" || :
[ ! -e "$T/pwned" ] || fail "settings_are_data: a settings value was run"

[ "$fails" -eq 0 ] || { echo "census-test: $fails failure(s)" >&2; exit 1; }
echo "census-test: OK"
