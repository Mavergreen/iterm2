#!/bin/sh
# platform: macOS-only -- configures a CMake fixture with the host's clang for Objective-C.
# spec: BUILD.md "Dependency dispositions" -- ColorPicker is rebuilt from the pinned archive's ColorPicker/ project as an
#       x86_64 framework (version A, install name @rpath/ColorPicker.framework/Versions/A/ColorPicker,
#       ARC on) at the build's 10.9 floor, not upstream's 10.8; iTerm2Shared and iTerm2 link it, and the
#       app finds it through @executable_path/../Frameworks. Nothing from the prebuilt
#       ColorPicker.framework, ColorPickerDemo or ColorPickerTests is ever an input.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-colorpicker-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
T=$(CDPATH= cd "$T" && pwd -P)
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
CMAKE=${SHIPYARD_CMAKE:-/usr/local/mavergreen/bin/shipyard-cmake}

S="$T/src/ColorPicker"
mkdir -p "$S/ColorPicker" "$S/ColorPicker.framework/Headers" "$S/ColorPickerDemo"
for f in CPKColorWell.m CPKPopover.m ColorPicker.h CPKColorWell.h CPKPopover.h CPKKDTree.h Info.plist Add.png Add@2x.png colors.txt; do
  : > "$S/ColorPicker/$f"
done
: > "$S/ColorPicker.framework/Headers/ColorPicker.h"; : > "$S/ColorPickerDemo/AppDelegate.m"
write_sources() { # EXTRA-LINE
  cat > "$T/colorpicker-sources.cmake" <<EOF
set(COLORPICKER_SOURCES [[ColorPicker/CPKColorWell.m]] [[ColorPicker/CPKPopover.m]])
set(COLORPICKER_PUBLIC_HEADERS [[ColorPicker/ColorPicker.h]] [[ColorPicker/CPKColorWell.h]] [[ColorPicker/CPKPopover.h]])
set(COLORPICKER_PRIVATE_HEADERS [[ColorPicker/CPKKDTree.h]])
set(COLORPICKER_RESOURCES [[ColorPicker/Add.png]] [[ColorPicker/Add@2x.png]] [[ColorPicker/colors.txt]])
$1
EOF
}
fixture() { # -- configure; the report is $T/b/report.txt
  rm -rf "$T/p" "$T/b"; mkdir -p "$T/p"
  cat > "$T/p/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.25)
project(fixture LANGUAGES C OBJC)
function(mavericks_target_sdk_metadata)
  cmake_parse_arguments(A "" "TARGET;SDK;RECIPES;OUTPUT_DIR" "IDS" \${ARGN})
  set_property(GLOBAL APPEND PROPERTY FIXTURE_METADATA "\${A_TARGET}:\${A_IDS}:\${A_SDK}")
endfunction()
include("$REPO_ROOT/cmake/ITermColorPicker.cmake")
iterm_add_colorpicker(SOURCES_FILE "$T/colorpicker-sources.cmake" SOURCE_DIR "$S"
                      SDK "$T/sdk" RECIPES "$T/recipes.json" METADATA_DIR "\${CMAKE_BINARY_DIR}/sdk-metadata")
add_library(iTerm2Shared STATIC "$S/ColorPicker/CPKColorWell.m")
add_executable(iTerm2 "$S/ColorPicker/CPKPopover.m")
iterm_link_colorpicker(iTerm2Shared iTerm2)
set(r "")
foreach(p INTERFACE_INCLUDE_DIRECTORIES RESOURCE TYPE FRAMEWORK FRAMEWORK_VERSION INSTALL_NAME_DIR OUTPUT_NAME SOURCES PUBLIC_HEADER
          COMPILE_OPTIONS OSX_ARCHITECTURES MACOSX_FRAMEWORK_IDENTIFIER LINK_LIBRARIES)
  get_target_property(v ColorPicker \${p})
  string(APPEND r "ColorPicker \${p} \${v}\n")
endforeach()
foreach(t iTerm2Shared iTerm2)
  foreach(p LINK_LIBRARIES BUILD_RPATH INSTALL_RPATH)
    get_target_property(v \${t} \${p})
    string(APPEND r "\${t} \${p} \${v}\n")
  endforeach()
endforeach()
string(APPEND r "DEPLOYMENT \${CMAKE_OSX_DEPLOYMENT_TARGET}\n")
get_property(m GLOBAL PROPERTY FIXTURE_METADATA)
string(APPEND r "METADATA \${m}\n")
file(WRITE "\${CMAKE_BINARY_DIR}/report.txt" "\${r}")
EOF
  "$CMAKE" -S "$T/p" -B "$T/b" -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_OBJC_COMPILER=/usr/bin/clang \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.9 -DCMAKE_OSX_ARCHITECTURES=x86_64 >"$T/log" 2>&1
}
has() { grep -F -- "$1 $2 " "$T/b/report.txt" | grep -qF -- "$3"; }
logged() { tr '\n' ' ' < "$T/log" | tr -s ' ' | grep -q -- "$1"; }

write_sources ''
if fixture; then
  has ColorPicker TYPE SHARED_LIBRARY || fail "ColorPicker is not a shared library"
  has ColorPicker FRAMEWORK TRUE || fail "ColorPicker is not a framework"
  has ColorPicker FRAMEWORK_VERSION A || fail "ColorPicker's framework version is not A"
  has ColorPicker INSTALL_NAME_DIR @rpath || fail "ColorPicker's install name is not under @rpath"
  has ColorPicker OUTPUT_NAME ColorPicker || fail "ColorPicker's product name"
  has ColorPicker SOURCES "$S/ColorPicker/CPKColorWell.m;$S/ColorPicker/CPKPopover.m" || fail "ColorPicker's sources"
  has ColorPicker PUBLIC_HEADER "$S/ColorPicker/ColorPicker.h;$S/ColorPicker/CPKColorWell.h;$S/ColorPicker/CPKPopover.h" \
    || fail "ColorPicker's public headers"
  has ColorPicker RESOURCE "$S/ColorPicker/Add.png;$S/ColorPicker/Add@2x.png;$S/ColorPicker/colors.txt" \
    || fail "ColorPicker's images and colors.txt are not its framework resources"
  has ColorPicker INTERFACE_INCLUDE_DIRECTORIES "$S" \
    || fail "ColorPicker does not give its linkers <ColorPicker/...> headers from its source"
  has ColorPicker COMPILE_OPTIONS -fobjc-arc || fail "ColorPicker lacks ARC"
  has ColorPicker MACOSX_FRAMEWORK_IDENTIFIER com.googlecode.iterm2.ColorPicker || fail "ColorPicker's bundle id"
  has ColorPicker LINK_LIBRARIES '-framework AppKit' || fail "ColorPicker links AppKit"
  grep -q '^ColorPicker OSX_ARCHITECTURES .*NOTFOUND' "$T/b/report.txt" || has ColorPicker OSX_ARCHITECTURES x86_64 \
    || fail "ColorPicker builds another arch"
  grep -q '^DEPLOYMENT 10.9$' "$T/b/report.txt" || fail "the floor is not 10.9"
  grep -q "^METADATA ColorPicker:foundation-array-generics-v2;[^:]*:$T/sdk$" "$T/b/report.txt" \
    || fail "ColorPicker does not get the SDK metadata overlay (it uses NSArray generics)"
  grep -q 'mmacosx-version-min\|10\.8' "$T/b/report.txt" && fail "ColorPicker sets its own deployment target"
  has iTerm2Shared LINK_LIBRARIES ColorPicker || fail "iTerm2Shared does not link ColorPicker"
  has iTerm2 LINK_LIBRARIES ColorPicker || fail "iTerm2 does not link ColorPicker"
  has iTerm2 BUILD_RPATH '@executable_path/../Frameworks' && has iTerm2 INSTALL_RPATH '@executable_path/../Frameworks' \
    || fail "iTerm2 does not find frameworks in @executable_path/../Frameworks"
  grep -q 'ColorPicker\.framework/\|ColorPickerDemo\|ColorPickerTests' "$T/b/report.txt" \
    && fail "a prebuilt, demo or test path is an input"
else
  cat "$T/log" >&2; fail "the fixture did not configure"
fi

write_sources 'list(APPEND COLORPICKER_SOURCES [[ColorPickerDemo/AppDelegate.m]])'
fixture && fail "a ColorPickerDemo source was accepted"
logged 'ColorPickerDemo/AppDelegate.m' || fail "the refusal does not name the demo source"
write_sources 'list(APPEND COLORPICKER_PUBLIC_HEADERS [[ColorPicker.framework/Headers/ColorPicker.h]])'
fixture && fail "a prebuilt framework header was accepted"
logged 'ColorPicker.framework/Headers/ColorPicker.h' || fail "the refusal does not name the prebuilt header"

[ "$fails" -eq 0 ] || { echo "colorpicker-target-test: $fails failure(s)" >&2; exit 1; }
echo "colorpicker-target-test: OK"
