cmake_minimum_required(VERSION 3.25)
# usage: sh build/prepare-inputs.sh "$TMPDIR/mm-build/mavergreen-iterm2-inputs"
#        shipyard-cmake --preset native   (on 10.9; --preset cross on a modern Mac)
#        shipyard-cmake --build --preset native
# spec: BUILD.md "Inputs" -- the verified inputs are read, and their clang22 selected, before project(), so
#       compiler detection runs only the verified family compiler.
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/ITermInputs.cmake")
project(iTerm2 VERSION ${ITERM_UPSTREAM_VERSION} LANGUAGES C OBJC)
iterm_check_compiler()

find_package(MavericksShipyard REQUIRED)
# platform: the family's clang22 compiles every target: the 3.0.15 sources use Objective-C lightweight
#           generics, which Apple clang on 10.9 cannot parse; BUILD.md "Inputs". Only the
#           AppleClang identity gate is off; the mode, pinned SDK and compatibility gates stay.
set(MAVERICKS_REQUIRE_APPLECLANG OFF)
include(Mavericks)
include(MavericksSDKMetadata)
include(MavericksXcodeInputs)
include(MavericksSparkle)

mavericks_export_xcode_sources(ITERM_SOURCES_FILE
  PROJECT "${ITERM_SOURCE_DIR}/iTerm2.xcodeproj"
  TARGETS iTerm2 iTerm2Shared SSKeychain image_decoder
  PREFIXES ITERM2 ITERM2_SHARED SSKEYCHAIN IMAGE_DECODER
  HOST_COMPILER "${ITERM_CLANG22_COMPILER}"
  OUTPUT_DIR "${CMAKE_BINARY_DIR}/xcode-inputs")

# spec: BUILD.md "Updates" -- Check for Updates launches the family updater; its bundle id is derived only by
#       shipyard's registry, never written here.
execute_process(COMMAND sh "${MAVERICKS_SHARED_DIR}/scripts/product-name.sh" updater-bundle-id iterm2
  OUTPUT_VARIABLE ITERM_UPDATER_BUNDLE_ID OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE _iterm_rc)
if(NOT _iterm_rc EQUAL 0)
  message(FATAL_ERROR "shipyard's registry does not answer for iterm2 (product-name.sh exited ${_iterm_rc}): install a shipyard that registers it")
endif()
execute_process(COMMAND sh "${MAVERICKS_SHARED_DIR}/scripts/product-name.sh" repo iterm2
  OUTPUT_VARIABLE _iterm_repo OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE _iterm_rc)
if(NOT _iterm_rc EQUAL 0)
  message(FATAL_ERROR "shipyard's registry names no repository for iterm2 (product-name.sh exited ${_iterm_rc})")
endif()
set(ITERM_RELEASES_URL "https://github.com/Mavergreen/${_iterm_repo}/releases")

mavericks_export_xcode_sources(ITERM_COLORPICKER_SOURCES_FILE
  PROJECT "${ITERM_SOURCE_DIR}/ColorPicker/ColorPicker.xcodeproj"
  TARGETS ColorPicker
  PREFIXES COLORPICKER
  HOST_COMPILER "${ITERM_CLANG22_COMPILER}"
  OUTPUT_DIR "${CMAKE_BINARY_DIR}/xcode-inputs")
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/ITermColorPicker.cmake")
iterm_add_colorpicker(SOURCES_FILE "${ITERM_COLORPICKER_SOURCES_FILE}" SOURCE_DIR "${ITERM_SOURCE_DIR}/ColorPicker"
  SDK "${CMAKE_OSX_SYSROOT}" RECIPES "${ITERM_RECAULK_RECIPES}" METADATA_DIR "${CMAKE_BINARY_DIR}/sdk-metadata")

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/ITermTargets.cmake")
iterm_add_targets(
  SOURCES_FILE "${ITERM_SOURCES_FILE}"
  SOURCE_DIR "${ITERM_SOURCE_DIR}"
  SDK "${CMAKE_OSX_SYSROOT}"
  RECIPES "${ITERM_RECAULK_RECIPES}"
  METADATA_DIR "${CMAKE_BINARY_DIR}/sdk-metadata"
  UPDATER_BUNDLE_ID "${ITERM_UPDATER_BUNDLE_ID}"
  RELEASES_URL "${ITERM_RELEASES_URL}"
  PRODUCT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/product"
  PATCH_DIR "${CMAKE_CURRENT_SOURCE_DIR}/patches")
iterm_link_colorpicker(iTerm2Shared iTerm2)

# spec: BUILD.md "Build evidence" -- driver tests check behavior against the built sources; record-build.sh runs
#       them on native builds
option(ITERM_DRIVERS "build the driver tests (target drivers, CTest label driver)" ON)
if(ITERM_DRIVERS)
  enable_testing()
  add_subdirectory(tests/drivers)
endif()

# spec: BUILD.md "Resources and the bundle" -- the first historical version is
#       <upstream>-mavericks.N, resolved from UPSTREAM_VERSION and the shipped tags.
include(MavericksVersion)
mavericks_resolve_version(ITERM_PRODUCT_VERSION)
# spec: BUILD.md "Updates" -- the family updater, with upstream's icon (maintainer, 2026-11-08), restarts a
#       running iTerm2 through its post-update helper once a new version is installed.
execute_process(COMMAND sh "${CMAKE_CURRENT_SOURCE_DIR}/build/make-icns.sh" "${ITERM_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/icon/iTerm2.icns"
  RESULT_VARIABLE _iterm_rc)
if(NOT _iterm_rc EQUAL 0)
  message(FATAL_ERROR "build/make-icns.sh could not make the updater's icon from ${ITERM_SOURCE_DIR}")
endif()
mavericks_add_updater_app(
  PRODUCT iterm2
  PRODUCT_NAME "Mavericks iTerm2"
  ICON "${CMAKE_BINARY_DIR}/icon/iTerm2.icns"
  VERSION "${ITERM_PRODUCT_VERSION}"
  CONFIRM_TITLE "Mavericks iTerm2 is up to date"
  CONFIRM_BODY "iTerm2 restarts now; sessions that can be restored come back."
  POST_UPDATE_HELPER "/Applications/Mavericks iTerm2.app/Contents/MacOS/restart-for-update")
if(NOT MAVERICKS_UPDATER_BUNDLE_ID STREQUAL ITERM_UPDATER_BUNDLE_ID)
  message(FATAL_ERROR "the updater is ${MAVERICKS_UPDATER_BUNDLE_ID} but patch 0004 launches ${ITERM_UPDATER_BUNDLE_ID}")
endif()

# spec: BUILD.md "Updates" -- the family updater's post-update helper, shipped in the app's MacOS/.
add_executable(restart-for-update "${CMAKE_CURRENT_SOURCE_DIR}/product/restart-for-update.m")
target_link_libraries(restart-for-update PRIVATE "-framework Cocoa")

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/ITermResources.cmake")
iterm_add_bundle(
  SOURCE_DIR "${ITERM_SOURCE_DIR}"
  ZIP "${ITERM_RESOURCES_ZIP}"
  ZIP_SHA256 "${ITERM_RESOURCES_SHA256}"
  UPSTREAM_VERSION "${ITERM_UPSTREAM_VERSION}"
  VERSION "${ITERM_PRODUCT_VERSION}"
  HOST_COMPILER "${ITERM_CLANG22_COMPILER}"
  OUTPUT_DIR "${CMAKE_BINARY_DIR}/resource-inputs")
# spec: BUILD.md "Updates" -- the updater ships with the app, so building the app builds it
add_dependencies(iTerm2-app ${MAVERICKS_UPDATER_TARGET})
