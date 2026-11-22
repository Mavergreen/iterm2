cmake_minimum_required(VERSION 3.25)
# usage: build/census.sh INPUTS_ROOT SETTINGS_FILE OUT_DIR (configures this project; never run it by hand)
# spec: BUILD.md "Census" -- every source of a candidate's targets, compiled with the shipping build's verified
#       clang22, pinned 10.9 SDK and Recaulk metadata, so its failures are Mavericks's, not the census's.
include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/ITermInputs.cmake")
get_filename_component(_iterm_cl_dir "${ITERM_CLANG22_COMPILER}" DIRECTORY)
foreach(_iterm_lang CXX OBJCXX)
  set(CMAKE_${_iterm_lang}_COMPILER "${_iterm_cl_dir}/clang++")
endforeach()
project(iTerm2Census LANGUAGES C CXX OBJC OBJCXX)
# spec: BUILD.md "Census" -- each compile's source and object, which census-classify.sh judges it by
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
iterm_check_compiler()

find_package(MavericksShipyard REQUIRED)
# platform: as in the product build, only the AppleClang identity gate is off; BUILD.md "Inputs"
set(MAVERICKS_REQUIRE_APPLECLANG OFF)
include(Mavericks)
include(MavericksSDKMetadata)
include(MavericksXcodeInputs)
include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/ITermMetadata.cmake")
include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/ITermCensus.cmake")

if(NOT DEFINED ITERM_CENSUS_PROJECT OR ITERM_CENSUS_PROJECT STREQUAL "")
  set(ITERM_CENSUS_PROJECT iTerm2.xcodeproj)
endif()
iterm_census(
  SETTINGS "${ITERM_CENSUS_SETTINGS}"
  SOURCE_DIR "${ITERM_SOURCE_DIR}"
  PROJECT "${ITERM_CENSUS_PROJECT}"
  SDK "${CMAKE_OSX_SYSROOT}"
  RECIPES "${ITERM_RECAULK_RECIPES}"
  METADATA_DIR "${CMAKE_BINARY_DIR}/sdk-metadata"
  LIST_FILE "${CMAKE_BINARY_DIR}/census-targets.tsv")
