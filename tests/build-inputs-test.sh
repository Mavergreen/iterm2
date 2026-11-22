#!/bin/sh
# platform: macOS-only -- prepare-inputs.sh reads installed Mavergreen product manifests with plutil.
# spec: BUILD.md "Inputs" -- build/prepare-inputs.sh OUTPUT_ROOT writes inputs.cmake and inputs.json only when
#       every pin verifies: source and resource hashes, the upstream version agreeing across pins, the
#       released shipyard modules, and the installed clang22/Recaulk at their pins. A failure leaves no
#       inputs file behind and never changes the checkout. Pin files are data: nothing in them is run.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-inputs-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
T=$(CDPATH= cd "$T" && pwd -P)

DIGEST=687aedf89cc860e273e16309b4b902a533d047db
INSTALLED=/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/scripts
[ -d "$INSTALLED" ] && [ -x /usr/local/mavergreen/bin/shipyard-cmake ] \
  || { echo "build-inputs-test: SKIP: no installed shipyard (the 10.9 acceptance guest has only a copy of its scripts)"; exit 77; }

mkdir -p "$T/src/iTerm2-$DIGEST/image_decoder" "$T/codeload/gnachman/iTerm2/tar.gz"
printf 'line one\nold\nline three\n' > "$T/src/iTerm2-$DIGEST/image_decoder/image_decoder.m"
(cd "$T/src" && COPYFILE_DISABLE=1 tar -czf "$T/codeload/gnachman/iTerm2/tar.gz/$DIGEST" "iTerm2-$DIGEST")
SRC_SHA=$(shasum -a 256 "$T/codeload/gnachman/iTerm2/tar.gz/$DIGEST" | cut -d' ' -f1)
printf 'not really a zip\n' > "$T/resources.zip"
RES_SHA=$(shasum -a 256 "$T/resources.zip" | cut -d' ' -f1)

tool() { # short version
  mkdir -p "$T/root/usr/local/mavergreen/$1/bin"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>version</key><string>%s</string></dict></plist>\n' "$2" \
    > "$T/root/usr/local/mavergreen/$1/mavergreen.plist"
}
tool clang22 22.1.8-mavericks.12
tool clang22-cross 22.1.8-mavericks.12
for c in clang22 clang22-cross; do
  printf '#!/bin/sh\nexit 0\n' > "$T/root/usr/local/mavergreen/$c/bin/clang"
  chmod 755 "$T/root/usr/local/mavergreen/$c/bin/clang"
done
tool recaulk 20261107.2
mkdir -p "$T/root/usr/local/mavergreen/recaulk/share/sdk-metadata"
echo '{}' > "$T/root/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json"

mkdir -p "$T/shipyard"
cp -R "$INSTALLED" "$T/shipyard/scripts"
for m in MavericksSDKMetadata MavericksXcodeInputs MavericksResourceInputs MavericksHostTools; do
  : > "$T/shipyard/$m.cmake"
done

fresh_repo() { # a copy of this checkout's build inputs, with fixture pins
  rm -rf "$T/repo" "$T/out"
  mkdir -p "$T/repo/components/iterm2" "$T/repo/components/iterm2-resources" \
    "$T/repo/components/clang22" "$T/repo/components/recaulk" "$T/repo/patches"
  cp -R "$REPO_ROOT/build" "$T/repo/build"
  mkdir -p "$T/repo/cmake"; cp -R "$REPO_ROOT/cmake/targets" "$T/repo/cmake/targets"
  cp "$REPO_ROOT/components/dependencies.tsv" "$T/repo/components/dependencies.tsv"
  printf 'REPO=https://github.com/gnachman/iTerm2\nREF=v3.0.15\nDIGEST=%s\nSHA256=%s\n' "$DIGEST" "$SRC_SHA" \
    > "$T/repo/components/iterm2/version"
  printf 'URL=file://%s\nSHA256=%s\nVERSION=3.0.15\n' "$T/resources.zip" "$RES_SHA" \
    > "$T/repo/components/iterm2-resources/version"
  echo 22.1.8-mavericks.12 > "$T/repo/components/clang22/version"
  echo 20261107.2 > "$T/repo/components/recaulk/version"
  echo 3.0.15 > "$T/repo/UPSTREAM_VERSION"
  printf -- '--- a/image_decoder/image_decoder.m\n+++ b/image_decoder/image_decoder.m\n@@ -1,3 +1,3 @@\n line one\n-old\n+new\n line three\n' \
    > "$T/repo/patches/0001-fixture.patch"
  rm -rf "$T/cache"
}
snapshot() { (cd "$T/repo" && find . -type f -exec shasum -a 256 {} + | sort); }
prepare() {
  SHIPYARD_SCRIPTS="$T/shipyard/scripts" MAVERGREEN_ROOT="$T/root" \
  MAVERICKS_CODELOAD="file://$T/codeload" MAVERICKS_SOURCE_CACHE="$T/cache" \
    sh "$T/repo/build/prepare-inputs.sh" "$T/out" >"$T/log" 2>&1
}
must_refuse() { # name -- prepare must fail, write no inputs, leave the checkout as it was
  before=$(snapshot)
  if prepare; then fail "$1: prepare-inputs.sh succeeded"; else echo "  refused $1: $(tail -1 "$T/log")"; fi
  [ ! -e "$T/out/inputs.cmake" ] && [ ! -e "$T/out/inputs.json" ] \
    || fail "$1: an inputs file was left behind"
  [ "$before" = "$(snapshot)" ] || fail "$1: the checkout changed"
  [ ! -e "$T/pwned" ] || fail "$1: a pin value was run as shell"
}
cmake_var() { # name -- the value inputs.cmake gives it, read back through cmake
  printf 'include("%s")\nmessage("${%s}")\n' "$T/out/inputs.cmake" "$1" > "$T/read.cmake"
  /usr/local/mavergreen/bin/shipyard-cmake -P "$T/read.cmake" 2>&1
}

fresh_repo
before=$(snapshot)
prepare || { cat "$T/log" >&2; fail "ok: prepare-inputs.sh failed"; }
[ -f "$T/out/inputs.cmake" ] && [ -f "$T/out/inputs.json" ] || fail "ok: inputs.cmake/inputs.json missing"
[ "$(sed -n 2p "$T/out/source/image_decoder/image_decoder.m")" = new ] || fail "ok: the patch was not applied"
[ "$(cat "$T/out/source/.mavergreen-source")" = "https://github.com/gnachman/iTerm2 $DIGEST $SRC_SHA" ] \
  || fail "ok: source stamp is not the pin"
[ "$before" = "$(snapshot)" ] || fail "ok: the checkout changed"
if [ -f "$T/out/inputs.cmake" ]; then
  [ "$(cmake_var ITERM_SOURCE_DIR)" = "$T/out/source" ] || fail "ok: ITERM_SOURCE_DIR"
  [ "$(cmake_var ITERM_RESOURCES_ZIP)" = "$T/cache/iTerm2-resources-3.0.15-$RES_SHA.zip" ] || fail "ok: ITERM_RESOURCES_ZIP"
  [ "$(cmake_var ITERM_RECAULK_RECIPES)" = "$T/root/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json" ] \
    || fail "ok: ITERM_RECAULK_RECIPES"
  case "$(cmake_var ITERM_CLANG22_COMPILER)" in
    "$T/root/usr/local/mavergreen/clang22/bin/clang"|"$T/root/usr/local/mavergreen/clang22-cross/bin/clang") ;;
    *) fail "ok: ITERM_CLANG22_COMPILER is not the verified tree's clang" ;;
  esac
  [ "$(cmake_var ITERM_DEPENDENCY_MANIFEST)" = "$T/repo/components/dependencies.tsv" ] || fail "ok: ITERM_DEPENDENCY_MANIFEST"
  [ "$(cmake_var ITERM_UPSTREAM_VERSION)" = 3.0.15 ] || fail "ok: ITERM_UPSTREAM_VERSION"
  [ "$(cmake_var ITERM_RESOURCES_SHA256)" = "$RES_SHA" ] || fail "ok: ITERM_RESOURCES_SHA256"
  [ "$(cmake_var ITERM_CLANG22_VERSION)" = 22.1.8-mavericks.12 ] || fail "ok: ITERM_CLANG22_VERSION is not the pin"
  printf 'file(READ "%s" j)\nstring(JSON v GET "${j}" source dir)\nmessage("${v}")\n' "$T/out/inputs.json" > "$T/json.cmake"
  [ "$(/usr/local/mavergreen/bin/shipyard-cmake -P "$T/json.cmake" 2>&1)" = "$T/out/source" ] || fail "ok: inputs.json is not valid JSON"
  grep -q "\"$(shasum -a 256 "$T/repo/patches/0001-fixture.patch" | cut -d' ' -f1)\"" "$T/out/inputs.json" \
    || fail "ok: inputs.json does not record the patch hash"
fi

mkdir -p "$T/out/source"; printf 'https://example.invalid/other %s %s\n' "$DIGEST" "$SRC_SHA" > "$T/out/source/.mavergreen-source"
sed 's/^SHA256=.*/SHA256=0000000000000000000000000000000000000000000000000000000000000000/' \
  "$T/repo/components/iterm2-resources/version" > "$T/v" && cat "$T/v" > "$T/repo/components/iterm2-resources/version"
must_refuse stale-stamp-bad-resource
fresh_repo
prepare && printf 'https://example.invalid/other\n' > "$T/out/source/.mavergreen-source" && prepare \
  || fail "rerun: prepare-inputs.sh failed"
[ "$(cat "$T/out/source/.mavergreen-source" 2>/dev/null)" = "https://github.com/gnachman/iTerm2 $DIGEST $SRC_SHA" ] \
  || fail "rerun: a tampered source stamp survived"

fresh_repo; sed "s/^SHA256=.*/SHA256=$RES_SHA/" "$T/repo/components/iterm2/version" > "$T/v"
cat "$T/v" > "$T/repo/components/iterm2/version"; must_refuse wrong-source-hash
fresh_repo; sed "s/^SHA256=.*/SHA256=$SRC_SHA/" "$T/repo/components/iterm2-resources/version" > "$T/v"
cat "$T/v" > "$T/repo/components/iterm2-resources/version"; must_refuse wrong-resource-hash
fresh_repo; echo 3.0.16 > "$T/repo/UPSTREAM_VERSION"; must_refuse upstream-version-mismatch
fresh_repo; sed 's/^VERSION=.*/VERSION=3.0.14/' "$T/repo/components/iterm2-resources/version" > "$T/v"
cat "$T/v" > "$T/repo/components/iterm2-resources/version"; must_refuse resource-version-mismatch
fresh_repo; mv "$T/shipyard/MavericksXcodeInputs.cmake" "$T/hidden.cmake"; must_refuse absent-released-module
mv "$T/hidden.cmake" "$T/shipyard/MavericksXcodeInputs.cmake"
fresh_repo; echo 22.1.8-mavericks.11 > "$T/repo/components/clang22/version"; must_refuse unverified-compiler-version
fresh_repo; mv "$T/root/usr/local/mavergreen/clang22" "$T/c1"; mv "$T/root/usr/local/mavergreen/clang22-cross" "$T/c2"
must_refuse uninstalled-compiler
mv "$T/c1" "$T/root/usr/local/mavergreen/clang22"; mv "$T/c2" "$T/root/usr/local/mavergreen/clang22-cross"
fresh_repo; echo 20261107.1 > "$T/repo/components/recaulk/version"; must_refuse unverified-recaulk
fresh_repo; mv "$T/root/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json" "$T/r.json"
must_refuse recaulk-without-recipes
mv "$T/r.json" "$T/root/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json"
fresh_repo; chmod 000 "$T/root/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json"
must_refuse unreadable-recipes; grep -q 'not readable' "$T/log" || fail "unreadable-recipes: the refusal does not say the recipes are unreadable"
chmod 644 "$T/root/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json"
fresh_repo; printf -- '--- a/image_decoder/image_decoder.m\n+++ b/image_decoder/image_decoder.m\n@@ -1,3 +1,3 @@\n line one\n-gone\n+new\n line three\n' \
  > "$T/repo/patches/0001-fixture.patch"; must_refuse stale-patch
fresh_repo; printf 'REPO=https://github.com/gnachman/iTerm2\nREF=v3.0.15\nDIGEST=$(touch %s/pwned)\nSHA256=%s\n' "$T" "$SRC_SHA" \
  > "$T/repo/components/iterm2/version"; must_refuse shell-in-pin
fresh_repo; printf 'URL=file://%s/a]==]b.zip\nSHA256=%s\nVERSION=3.0.15\n' "$T" "$RES_SHA" \
  > "$T/repo/components/iterm2-resources/version"; must_refuse cmake-syntax-in-pin

fresh_repo; Q="$T/quote\"dir"
SHIPYARD_SCRIPTS="$T/shipyard/scripts" MAVERGREEN_ROOT="$T/root" MAVERICKS_CODELOAD="file://$T/codeload" \
  MAVERICKS_SOURCE_CACHE="$T/cache" sh "$T/repo/build/prepare-inputs.sh" "$Q" >"$T/log" 2>&1 || fail "quote: prepare failed"
printf 'file(READ "%s" j)\nstring(JSON v GET "${j}" source dir)\nmessage("${v}")\n' "$Q/inputs.json" | sed 's/quote"dir/quote\\"dir/' > "$T/json.cmake"
[ "$(/usr/local/mavergreen/bin/shipyard-cmake -P "$T/json.cmake" 2>&1)" = "$Q/source" ] || fail "quote: inputs.json is not valid JSON for a path with a quote"

# spec: BUILD.md "Inputs" -- a candidate upstream is prepared through this same path, with its pins from
#       ITERM_PINS_DIR and its patches from ITERM_PATCHES_DIR, and the shipping pins never move.
DIGEST2=1111111111111111111111111111111111111111
mkdir -p "$T/src/iTerm2-$DIGEST2/image_decoder"
printf 'candidate\n' > "$T/src/iTerm2-$DIGEST2/image_decoder/image_decoder.m"
(cd "$T/src" && COPYFILE_DISABLE=1 tar -czf "$T/codeload/gnachman/iTerm2/tar.gz/$DIGEST2" "iTerm2-$DIGEST2")
SRC2_SHA=$(shasum -a 256 "$T/codeload/gnachman/iTerm2/tar.gz/$DIGEST2" | cut -d' ' -f1)
cand_pins() { # dir
  rm -rf "$1"; mkdir -p "$1/components/iterm2" "$1/components/iterm2-resources"
  printf 'REPO=https://github.com/gnachman/iTerm2\nREF=v3.1.7\nDIGEST=%s\nSHA256=%s\n' "$DIGEST2" "$SRC2_SHA" \
    > "$1/components/iterm2/version"
  printf 'URL=file://%s\nSHA256=%s\nVERSION=3.1.7\n' "$T/resources.zip" "$RES_SHA" > "$1/components/iterm2-resources/version"
  echo 3.1.7 > "$1/UPSTREAM_VERSION"
  echo '# fixture table' > "$1/targets.cmake"
}
cand() { # pins-dir patches-dir
  ITERM_PINS_DIR="$1" ITERM_PATCHES_DIR="$2" SHIPYARD_SCRIPTS="$T/shipyard/scripts" MAVERGREEN_ROOT="$T/root" \
  MAVERICKS_CODELOAD="file://$T/codeload" MAVERICKS_SOURCE_CACHE="$T/cache" \
    sh "$T/repo/build/prepare-inputs.sh" "$T/out" >"$T/log" 2>&1
}
fresh_repo; cand_pins "$T/pins"; mkdir -p "$T/nopatches"; before=$(snapshot)
cand "$T/pins" "$T/nopatches" || { cat "$T/log" >&2; fail "pins_dir_overrides_source_pins: prepare failed"; }
grep -q '"ref": "v3.1.7"' "$T/out/inputs.json" 2>/dev/null || fail "pins_dir_overrides_source_pins: inputs.json does not name v3.1.7"
[ "$(cat "$T/out/source/.mavergreen-source" 2>/dev/null)" = "https://github.com/gnachman/iTerm2 $DIGEST2 $SRC2_SHA" ] \
  || fail "pins_dir_overrides_source_pins: the source is not the candidate's"
[ "$before" = "$(snapshot)" ] || fail "pins_dir_overrides_source_pins: the checkout changed"
grep -q "\"pins_dir\": \"$T/pins\"" "$T/out/inputs.json" 2>/dev/null || fail "pins_dir_overrides_source_pins: inputs.json does not record pins_dir"
[ "$(cat "$T/out/source/image_decoder/image_decoder.m" 2>/dev/null)" = candidate ] \
  || fail "patches_dir_empty_applies_nothing: the candidate source was patched"
grep -q '"patches": \[\]' "$T/out/inputs.json" 2>/dev/null || fail "patches_dir_empty_applies_nothing: inputs.json lists patches"
fresh_repo; cand_pins "$T/pins"
if cand pins "$T/nopatches"; then fail "pins_dir_relative_refused: accepted"; fi
grep -q 'ITERM_PINS_DIR must be absolute' "$T/log" || fail "pins_dir_relative_refused: $(tail -1 "$T/log")"
fresh_repo; cand_pins "$T/repo/cand"
if cand "$T/repo/cand" "$T/nopatches"; then fail "pins_dir_inside_checkout_refused: accepted"; fi
grep -q 'ITERM_PINS_DIR is inside the checkout' "$T/log" || fail "pins_dir_inside_checkout_refused: $(tail -1 "$T/log")"

# spec: candidates/README.md -- build/candidate.sh VERSION OUTPUT_ROOT prepares the tracked candidate
#       candidates/VERSION: its pins and its patches always together, from inside the checkout
fresh_repo; cand_pins "$T/repo/candidates/9.0"; mkdir -p "$T/repo/candidates/9.0/patches"; before=$(snapshot)
candidate() { # version
  SHIPYARD_SCRIPTS="$T/shipyard/scripts" MAVERGREEN_ROOT="$T/root" \
  MAVERICKS_CODELOAD="file://$T/codeload" MAVERICKS_SOURCE_CACHE="$T/cache" \
    sh "$T/repo/build/candidate.sh" "$1" "$T/out" >"$T/log" 2>&1
}
candidate 9.0 || { tail -5 "$T/log" >&2; fail "candidate_sh_sets_both_dirs: candidate.sh failed"; }
grep -q "\"pins_dir\": \"$T/repo/candidates/9.0\"" "$T/out/inputs.json" 2>/dev/null \
  || fail "candidate_sh_sets_both_dirs: inputs.json pins_dir is not the candidate's"
grep -q "\"patches_dir\": \"$T/repo/candidates/9.0/patches\"" "$T/out/inputs.json" 2>/dev/null \
  || fail "candidate_sh_sets_both_dirs: inputs.json patches_dir is not the candidate's"
[ "$(cat "$T/out/source/image_decoder/image_decoder.m" 2>/dev/null)" = candidate ] \
  || fail "candidate_sh_sets_both_dirs: the shipping patches were applied to the candidate"
[ "$before" = "$(snapshot)" ] || fail "candidate_sh_sets_both_dirs: the checkout changed"
if candidate 9.9.9; then fail "unknown_candidate_refused: accepted"; fi
grep -q 'no candidates/9.9.9' "$T/log" || fail "unknown_candidate_refused: $(tail -1 "$T/log")"
if candidate ../patches; then fail "candidate_name_refused: accepted"; fi
grep -q 'candidate name' "$T/log" || fail "candidate_name_refused: $(tail -1 "$T/log")"

# spec: BUILD.md "Targets" -- the inputs name the targets table: the shipping version's, or the candidate's own
fresh_repo; prepare || { tail -3 "$T/log" >&2; fail "shipping_inputs_name_shipping_table: prepare failed"; }
[ "$(cmake_var ITERM_TARGETS_FILE)" = "$T/repo/cmake/targets/3.0.15.cmake" ] \
  || fail "shipping_inputs_name_shipping_table: $(cmake_var ITERM_TARGETS_FILE)"
fresh_repo; cand_pins "$T/repo/candidates/9.0"; mkdir -p "$T/repo/candidates/9.0/patches"
candidate 9.0 || { tail -3 "$T/log" >&2; fail "candidate_inputs_name_candidate_table: candidate.sh failed"; }
[ "$(cmake_var ITERM_TARGETS_FILE)" = "$T/repo/candidates/9.0/targets.cmake" ] \
  || fail "candidate_inputs_name_candidate_table: $(cmake_var ITERM_TARGETS_FILE)"
rm "$T/repo/candidates/9.0/targets.cmake"
if candidate 9.0; then fail "candidate_without_table_refused: accepted"; fi
grep -q 'targets table' "$T/log" || fail "candidate_without_table_refused: $(tail -1 "$T/log")"

[ "$fails" -eq 0 ] || { echo "build-inputs-test: $fails failure(s)" >&2; exit 1; }
echo "build-inputs-test: OK"
