#!/bin/sh
# platform: macOS-only -- configures a CMake fixture with the host's clang for Objective-C.
# spec: BUILD.md "Targets" -- cmake/ITermTargets.cmake turns the exported source lists into the four production
#       targets with the pinned Deployment settings, per target: iTerm2Shared without ARC and with
#       sources/iTerm2.pch, SSKeychain with ARC and its own prefix header, image_decoder with ARC,
#       in-tree targets linked directly, APR from the pinned SDK's dylib (never a .tbd), the SDK
#       metadata overlay only on the targets that opt in, the Core Data model never compiled, and an
#       unknown setting or exported variable refused rather than dropped.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-targets-test.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
T=$(CDPATH= cd "$T" && pwd -P)
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
CMAKE=${SHIPYARD_CMAKE:-/usr/local/mavergreen/bin/shipyard-cmake}

S="$T/src"; SDK="$T/sdk"
mkdir -p "$S/sources" "$S/ThirdParty/SSKeychain" "$S/image_decoder" "$S/Model.xcdatamodeld" "$SDK/usr/lib"
for f in sources/main.m sources/iTermApplication.m sources/Shared.m sources/vt100.c \
         ThirdParty/SSKeychain/SSKeychain.m image_decoder/image_decoder.m; do : > "$S/$f"; done
mkdir -p "$T/product"; : > "$T/product/SUUpdater.m"; : > "$T/product/iTermFamilyVersion.m"
: > "$S/sources/iTerm2.pch"; : > "$S/ThirdParty/SSKeychain/SSKeychain-Prefix.pch"
for l in aprutil-1 icucore ncurses; do : > "$SDK/usr/lib/lib$l.dylib"; done
: > "$SDK/usr/lib/libaprutil-1.tbd"
cat > "$T/sources.cmake" <<'EOF'
set(ITERM2_SOURCES [[sources/main.m]] [[sources/iTermApplication.m]])
set(ITERM2_SHARED_SOURCES [[sources/Shared.m]] [[sources/vt100.c]])
set(ITERM2_SHARED_MODELS [[Model.xcdatamodeld]])
set(ITERM2_SHARED_INCLUDE_DIRS [[sources]])
set(ITERM2_SHARED_PUBLIC_HEADERS)
set(SSKEYCHAIN_SOURCES [[ThirdParty/SSKeychain/SSKeychain.m]])
set(IMAGE_DECODER_SOURCES [[image_decoder/image_decoder.m]])
set(IMAGE_DECODER_RESOURCES)
EOF

fixture() { # EXTRA-CMAKE -- configure the fixture project; the report is $T/b/report.txt
  rm -rf "$T/p" "$T/b"; mkdir -p "$T/p"
  cat > "$T/p/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.25)
project(fixture LANGUAGES C OBJC)
function(mavericks_target_sdk_metadata)
  cmake_parse_arguments(A "" "TARGET;SDK;RECIPES;OUTPUT_DIR" "IDS" \${ARGN})
  set_property(GLOBAL APPEND PROPERTY FIXTURE_METADATA "\${A_TARGET}:\${A_IDS}:\${A_SDK}")
endfunction()
include("$REPO_ROOT/cmake/ITermTargets.cmake")
$1
iterm_add_targets(SOURCES_FILE "$T/sources.cmake" SOURCE_DIR "$S" SDK "$SDK"
                  RECIPES "$T/recipes.json" METADATA_DIR "\${CMAKE_BINARY_DIR}/sdk-metadata"
                  UPDATER_BUNDLE_ID dev.example.iterm2.updater RELEASES_URL https://example.invalid/iterm2/releases
                  PRODUCT_DIR "$T/product")
set(r "")
foreach(t iTerm2 iTerm2Shared SSKeychain image_decoder)
  foreach(p TYPE SOURCES COMPILE_OPTIONS INCLUDE_DIRECTORIES LINK_LIBRARIES LINK_OPTIONS MANUALLY_ADDED_DEPENDENCIES COMPILE_DEFINITIONS)
    get_target_property(v \${t} \${p})
    string(APPEND r "\${t} \${p} \${v}\n")
  endforeach()
endforeach()
get_property(m GLOBAL PROPERTY FIXTURE_METADATA)
string(APPEND r "METADATA \${m}\n")
file(WRITE "\${CMAKE_BINARY_DIR}/report.txt" "\${r}")
EOF
  "$CMAKE" -S "$T/p" -B "$T/b" -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_OBJC_COMPILER=/usr/bin/clang \
    >"$T/log" 2>&1
}
has() { grep -qF -- "$1 $2 " "$T/b/report.txt" && grep -F -- "$1 $2 " "$T/b/report.txt" | grep -qF -- "$3"; }
hasnt() { ! grep -F -- "$1 $2 " "$T/b/report.txt" | grep -qF -- "$3"; }

if fixture ''; then
  [ -z "${KEEP:-}" ] || cp "$T/b/report.txt" "$T/report-ok.txt"
  has iTerm2 TYPE EXECUTABLE || fail "iTerm2 is an executable"
  has iTerm2Shared TYPE STATIC_LIBRARY || fail "iTerm2Shared is a static library"
  has SSKeychain TYPE STATIC_LIBRARY || fail "SSKeychain is a static library"
  has image_decoder TYPE EXECUTABLE || fail "image_decoder is an executable"
  has iTerm2 SOURCES "$S/sources/main.m;$S/sources/iTermApplication.m;$T/product/SUUpdater.m;$T/product/iTermFamilyVersion.m" || fail "iTerm2's sources (with the SUUpdater nib shim)"
  has iTerm2Shared COMPILE_DEFINITIONS 'ITERM_UPDATER_BUNDLE_ID="dev.example.iterm2.updater"' \
    || fail "iTerm2Shared, which compiles iTermApplicationDelegate.m, lacks ITERM_UPDATER_BUNDLE_ID"
  has iTerm2Shared COMPILE_DEFINITIONS 'ITERM_RELEASES_URL="https://example.invalid/iterm2/releases"' \
    || fail "iTerm2Shared lacks ITERM_RELEASES_URL"
  has iTerm2Shared SOURCES "$S/sources/Shared.m;$S/sources/vt100.c" || fail "iTerm2Shared's sources"
  hasnt iTerm2Shared SOURCES xcdatamodeld || fail "the Core Data model is compiled"
  has SSKeychain SOURCES "$S/ThirdParty/SSKeychain/SSKeychain.m" || fail "SSKeychain's sources"
  has image_decoder SOURCES "$S/image_decoder/image_decoder.m" || fail "image_decoder's sources"
  hasnt iTerm2Shared COMPILE_OPTIONS -fobjc-arc || fail "iTerm2Shared has ARC"
  has iTerm2Shared COMPILE_OPTIONS "-include $S/sources/iTerm2.pch" || fail "iTerm2Shared's prefix header"
  has SSKeychain COMPILE_OPTIONS -fobjc-arc || fail "SSKeychain lacks ARC"
  has SSKeychain COMPILE_OPTIONS "-include $S/ThirdParty/SSKeychain/SSKeychain-Prefix.pch" || fail "SSKeychain's prefix header"
  has image_decoder COMPILE_OPTIONS -fobjc-arc || fail "image_decoder lacks ARC"
  hasnt iTerm2 COMPILE_OPTIONS -fobjc-arc || fail "iTerm2 has ARC"
  hasnt iTerm2 COMPILE_OPTIONS -include || fail "iTerm2 has a prefix header"
  has iTerm2 INCLUDE_DIRECTORIES "$S;$S/ThirdParty" || fail "iTerm2's header search paths"
  has iTerm2Shared INCLUDE_DIRECTORIES "$S/sources" || fail "iTerm2Shared's exported include dirs"
  has iTerm2 LINK_LIBRARIES iTerm2Shared || fail "iTerm2 links iTerm2Shared directly"
  has iTerm2Shared LINK_LIBRARIES SSKeychain || fail "iTerm2Shared links SSKeychain directly"
  has iTerm2 MANUALLY_ADDED_DEPENDENCIES image_decoder || fail "iTerm2 depends on image_decoder"
  has image_decoder LINK_LIBRARIES "$SDK/usr/lib/libaprutil-1.dylib" || fail "image_decoder links the SDK's APR dylib"
  has iTerm2 LINK_LIBRARIES "$SDK/usr/lib/libaprutil-1.dylib" || fail "iTerm2 links the SDK's APR dylib"
  ! grep -q '\.tbd' "$T/b/report.txt" || fail "a .tbd is linked"
  has iTerm2 LINK_OPTIONS -ObjC || fail "iTerm2 links with -ObjC"
  for fw in Growl NMSSH Sparkle; do
    ! grep -q "$fw" "$T/b/report.txt" || fail "$fw is still linked"
  done
  grep -q "^METADATA .*iTerm2Shared:foundation-array-generics-v1:$SDK" "$T/b/report.txt" \
    || fail "iTerm2Shared does not get the SDK metadata overlay"
  grep -q "^METADATA .*image_decoder:foundation-array-generics-v1:$SDK" "$T/b/report.txt" \
    || fail "image_decoder does not get the SDK metadata overlay"
  ! grep -q '^METADATA .*SSKeychain' "$T/b/report.txt" || fail "SSKeychain gets the overlay without opting in"
else
  cat "$T/log" >&2; fail "the fixture did not configure"
fi

fixture 'list(APPEND ITERM_ROW_SSKeychain WARNINGS -Wall)' && fail "an unknown setting was accepted" \
  || grep -q 'WARNINGS' "$T/log" || fail "the refusal does not name the unknown setting"
cp "$T/sources.cmake" "$T/sources.keep"
echo 'set(SSKEYCHAIN_LINK_FLAGS [[-lfoo]])' >> "$T/sources.cmake"
fixture '' && fail "an unknown exported variable was accepted" \
  || grep -q 'SSKEYCHAIN_LINK_FLAGS' "$T/log" || fail "the refusal does not name the exported variable"
cp "$T/sources.keep" "$T/sources.cmake"
rm "$SDK/usr/lib/libaprutil-1.dylib"
fixture '' && fail "a missing SDK APR dylib was accepted" \
  || grep -q 'libaprutil-1.dylib' "$T/log" || fail "the refusal does not name the missing dylib"

for c in /usr/local/mavergreen/clang22/bin/clang /usr/local/mavergreen/clang22-cross/bin/clang; do
  [ -x "$c" ] && CLANG22=$c && break
done
logged() { tr '\n' ' ' < "$T/log" | tr -s ' ' | grep -q -- "$1"; }  # CMake wraps its messages
gate() { # COMPILER [EXTRA-ARGS...] -- configure the real CMakeLists with fixture inputs naming COMPILER
  c=$1; shift
  rm -rf "$T/g"; mkdir -p "$T/g"
  : > "$T/g/resources.zip"; : > "$T/g/recipes.json"; : > "$T/g/deps.tsv"
  printf 'set(ITERM_UPSTREAM_VERSION 3.0.15)\nset(ITERM_SOURCE_DIR [[%s]])\nset(ITERM_RESOURCES_ZIP [[%s]])\nset(ITERM_RESOURCES_SHA256 %s)\nset(ITERM_CLANG22_VERSION %s)\nset(ITERM_RECAULK_RECIPES [[%s]])\nset(ITERM_CLANG22_COMPILER [[%s]])\nset(ITERM_DEPENDENCY_MANIFEST [[%s]])\nset(ITERM_MODE native)\n' \
    "$S" "$T/g/resources.zip" "${GATE_SHA:-90e6f2bd3eb2d245f4ab2c9f856c627c8a1536bac024fb3989db417bc3147565}" \
    "${GATE_PIN:-22.1.8-mavericks.12}" "$T/g/recipes.json" "$c" "$T/g/deps.tsv" > "$T/g/inputs.cmake"
  "$CMAKE" -S "$REPO_ROOT" -B "$T/g/b" "$@" >"$T/log" 2>&1
}
gate /usr/bin/clang -DITERM_INPUTS_FILE="$T/g/inputs.cmake" && fail "Apple clang was accepted"
logged "not the family's clang 22" || { cat "$T/log" >&2; fail "Apple clang was not refused by identity"; }
gate "${CLANG22:-/nonexistent}" -DITERM_INPUTS_FILE="$T/g/inputs.cmake" -DCMAKE_OBJC_COMPILER=/usr/bin/clang \
  && fail "a cache compiler override was accepted"
logged "this build compiles only with the" || fail "a cache compiler override was not refused"
gate "${CLANG22:-/nonexistent}" && fail "a configure without ITERM_INPUTS_FILE was accepted"
logged "ITERM_INPUTS_FILE is not set" || fail "a missing ITERM_INPUTS_FILE was not refused"
if [ -n "${CLANG22:-}" ]; then
  gate "$CLANG22" -DITERM_INPUTS_FILE="$T/g/inputs.cmake" || :
  { logged "not the family's clang 22" || logged "compiles only with"; } && fail "the installed clang22 was refused"
  grep -q 'Check for working OBJC compiler: '"$CLANG22"' - skipped\|The OBJC compiler identification is Clang 22' "$T/log" \
    || fail "configure did not detect the installed clang22"
  GATE_PIN=22.1.7-mavericks.1 gate "$CLANG22" -DITERM_INPUTS_FILE="$T/g/inputs.cmake" && fail "a clang22 other than the pin was accepted"
  logged "not the pinned clang22 22.1.7" || fail "a clang22 other than the pin was not refused by version"
  GATE_SHA=0123abcd gate "$CLANG22" -DITERM_INPUTS_FILE="$T/g/inputs.cmake" && fail "a short resource SHA-256 was accepted"
  logged "ITERM_RESOURCES_SHA256" || fail "a short resource SHA-256 was not refused by name"
else
  fail "no installed clang22 or clang22-cross to test the accepted compiler"
fi

[ "$fails" -eq 0 ] || { echo "target-settings-test: $fails failure(s)" >&2; exit 1; }
echo "target-settings-test: OK"
