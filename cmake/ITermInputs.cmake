# ITermInputs.cmake -- included BEFORE project(): reads build/prepare-inputs.sh's verified inputs and
# selects their compiler, so compiler detection already runs the verified family clang22.
#
# spec: BUILD.md "Inputs" -- configure receives the absolute path of OUTPUT_ROOT/inputs.cmake as ITERM_INPUTS_FILE
#       (the presets set it); every input must be there and absolute; C and Objective-C both compile
#       with ITERM_CLANG22_COMPILER, and a compiler chosen any other way (the cache, the environment,
#       PATH) is refused rather than accepted.
# After project(), iterm_check_compiler() proves the detected compiler is the pinned clang22's version.

if(NOT DEFINED ITERM_INPUTS_FILE OR "${ITERM_INPUTS_FILE}" STREQUAL "")
  message(FATAL_ERROR
    "ITERM_INPUTS_FILE is not set. Run build/prepare-inputs.sh OUTPUT_ROOT, then configure with a preset "
    "(shipyard-cmake --preset native or cross), which passes OUTPUT_ROOT/inputs.cmake.")
endif()
if(NOT IS_ABSOLUTE "${ITERM_INPUTS_FILE}" OR NOT EXISTS "${ITERM_INPUTS_FILE}")
  message(FATAL_ERROR
    "ITERM_INPUTS_FILE ${ITERM_INPUTS_FILE} is not an existing absolute path: run build/prepare-inputs.sh "
    "with the OUTPUT_ROOT the preset names.")
endif()
include("${ITERM_INPUTS_FILE}")
# spec: BUILD.md "Build evidence" -- ITERM_UNRELEASED_RECIPES tries a Recaulk working tree's recipes while
#       declaration fixes are iterated; the build records it, and build/record-build.sh never calls it PASS
if(DEFINED ITERM_UNRELEASED_RECIPES AND NOT "${ITERM_UNRELEASED_RECIPES}" STREQUAL "")
  if(NOT IS_ABSOLUTE "${ITERM_UNRELEASED_RECIPES}" OR NOT EXISTS "${ITERM_UNRELEASED_RECIPES}")
    message(FATAL_ERROR "ITERM_UNRELEASED_RECIPES must be an existing absolute path (got '${ITERM_UNRELEASED_RECIPES}').")
  endif()
  message(WARNING "using UNRELEASED recipes ${ITERM_UNRELEASED_RECIPES}: this build can never be a release candidate.")
  set(ITERM_RECAULK_RECIPES "${ITERM_UNRELEASED_RECIPES}")
  set(ITERM_UNRELEASED_INPUTS ON CACHE BOOL "built with unreleased Recaulk recipes" FORCE)
else()
  set(ITERM_UNRELEASED_INPUTS OFF CACHE BOOL "built with unreleased Recaulk recipes" FORCE)
endif()
foreach(_iterm_v ITERM_SOURCE_DIR ITERM_RESOURCES_ZIP ITERM_RECAULK_RECIPES ITERM_CLANG22_COMPILER
                 ITERM_DEPENDENCY_MANIFEST)
  if(NOT DEFINED ${_iterm_v} OR NOT IS_ABSOLUTE "${${_iterm_v}}" OR NOT EXISTS "${${_iterm_v}}")
    message(FATAL_ERROR "${ITERM_INPUTS_FILE} gives ${_iterm_v} no existing absolute path: prepare the inputs again.")
  endif()
endforeach()
foreach(_iterm_check
    "ITERM_UPSTREAM_VERSION=^[0-9]+(\\.[0-9]+)*$"
    "ITERM_RESOURCES_SHA256=^[0-9a-f]+$"
    "ITERM_CLANG22_VERSION=^[0-9]+\\.[0-9]+\\.[0-9]+-mavericks\\.[1-9][0-9]*$"
    "ITERM_MODE=^(native|cross)$")
  string(FIND "${_iterm_check}" "=" _iterm_eq)
  string(SUBSTRING "${_iterm_check}" 0 ${_iterm_eq} _iterm_v)
  math(EXPR _iterm_eq "${_iterm_eq} + 1")
  string(SUBSTRING "${_iterm_check}" ${_iterm_eq} -1 _iterm_re)
  string(LENGTH "${${_iterm_v}}" _iterm_len)
  if(NOT "${${_iterm_v}}" MATCHES "${_iterm_re}" OR (_iterm_v STREQUAL "ITERM_RESOURCES_SHA256" AND NOT _iterm_len EQUAL 64))
    message(FATAL_ERROR "${ITERM_INPUTS_FILE} has no valid ${_iterm_v} ('${${_iterm_v}}'): prepare the inputs again.")
  endif()
endforeach()
unset(_iterm_check)
unset(_iterm_eq)
unset(_iterm_v)
unset(_iterm_re)
unset(_iterm_len)
if(DEFINED MAVERICKS_EXPECTED_MODE AND NOT MAVERICKS_EXPECTED_MODE STREQUAL ITERM_MODE)
  message(FATAL_ERROR
    "the inputs were prepared for a ${ITERM_MODE} build, but this configure is ${MAVERICKS_EXPECTED_MODE}: "
    "prepare them on this host.")
endif()
foreach(_iterm_lang C OBJC)
  if(DEFINED CMAKE_${_iterm_lang}_COMPILER
     AND NOT "${CMAKE_${_iterm_lang}_COMPILER}" STREQUAL "${ITERM_CLANG22_COMPILER}")
    message(FATAL_ERROR
      "CMAKE_${_iterm_lang}_COMPILER is ${CMAKE_${_iterm_lang}_COMPILER}, but this build compiles only with the "
      "verified ${ITERM_CLANG22_COMPILER}: remove the override (or the build directory) and configure again.")
  endif()
  set(CMAKE_${_iterm_lang}_COMPILER "${ITERM_CLANG22_COMPILER}")
endforeach()
unset(_iterm_lang)
unset(_iterm_v)

function(iterm_check_compiler)
  string(REGEX REPLACE "-mavericks\\..*$" "" pinned "${ITERM_CLANG22_VERSION}")
  foreach(lang C OBJC)
    if(NOT CMAKE_${lang}_COMPILER_ID STREQUAL "Clang" OR NOT CMAKE_${lang}_COMPILER_VERSION MATCHES "^22\\.")
      message(FATAL_ERROR
        "${CMAKE_${lang}_COMPILER} identifies as ${CMAKE_${lang}_COMPILER_ID} ${CMAKE_${lang}_COMPILER_VERSION}, "
        "not the family's clang 22.")
    endif()
    if(NOT CMAKE_${lang}_COMPILER_VERSION VERSION_EQUAL pinned)
      message(FATAL_ERROR
        "${CMAKE_${lang}_COMPILER} is clang ${CMAKE_${lang}_COMPILER_VERSION}, not the pinned clang22 ${pinned} "
        "(${ITERM_CLANG22_VERSION}): install the pinned release and prepare the inputs again.")
    endif()
  endforeach()
endfunction()
