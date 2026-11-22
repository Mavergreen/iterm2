# ITermCensus.cmake -- one object library per target of a candidate upstream, for build/census.sh.
#
# iterm_census(SETTINGS <abs> SOURCE_DIR <abs> PROJECT <rel .xcodeproj> SDK <abs> RECIPES <abs>
#              METADATA_DIR <abs> LIST_FILE <abs>)
#   SETTINGS is a key file read as data, never evaluated: blank lines and # comments are skipped, every other
#   line is KEY=VALUE, and each TARGET= line starts a block. Every block sets exactly these keys:
#     TARGET         the Xcode target's name in PROJECT
#     PREFIX         the exporter's variable prefix for it (as ITermTargets.cmake's EXPORT_PREFIX)
#     ARC            ON | OFF
#     PREFIX_HEADER  relative to SOURCE_DIR, or empty
#     C_STANDARD     99 | 11
#     C_EXTENSIONS   ON | OFF
#     INCLUDES       space-separated directories relative to SOURCE_DIR ("." is SOURCE_DIR), or empty
#     DEFINES        space-separated NAME or NAME=VALUE (VALUE bare, or "quoted" without spaces), or empty:
#                    what the product build defines for that target (3.0.15's ITERM_UPDATER_BUNDLE_ID)
#     METADATA       ON | OFF: the Recaulk SDK-metadata overlay
#   Each block is copied by hand from that candidate's pbxproj, like ITermTargets.cmake's rows; a missing,
#   repeated or unknown key, or a target PROJECT does not have, is refused, never defaulted.
#   LIST_FILE gets one "<prefix>\t<target>" line per target (census_<prefix> is its object library).
#
# spec: BUILD.md "Census" -- compiled at -O0 with no error limit: the census wants every diagnostic, not code.

set(_ITERM_CENSUS_KEYS TARGET PREFIX ARC PREFIX_HEADER C_STANDARD C_EXTENSIONS INCLUDES DEFINES METADATA)

function(_iterm_census_check key value where)
  if(key STREQUAL "TARGET")
    set(re "^[A-Za-z0-9 _.+-]+$")
  elseif(key STREQUAL "PREFIX")
    set(re "^[A-Z0-9_]+$")
  elseif(key MATCHES "^(ARC|C_EXTENSIONS|METADATA)$")
    set(re "^(ON|OFF)$")
  elseif(key STREQUAL "C_STANDARD")
    set(re "^(99|11)$")
  elseif(key STREQUAL "PREFIX_HEADER")
    set(re "^([A-Za-z0-9_+-][A-Za-z0-9_./+-]*)?$")
  elseif(key STREQUAL "DEFINES")
    set(d "[A-Za-z_][A-Za-z0-9_]*(=(\"[A-Za-z0-9._/:+-]*\"|[A-Za-z0-9._/:+-]+))?")
    set(re "^(${d}( ${d})*)?$")
  elseif(key STREQUAL "INCLUDES")
    set(re "^([A-Za-z0-9_.+-][A-Za-z0-9_./+-]*( [A-Za-z0-9_.+-][A-Za-z0-9_./+-]*)*)?$")
  endif()
  if(NOT "${value}" MATCHES "${re}" OR (NOT key STREQUAL "DEFINES" AND "${value}" MATCHES "(^|/)\\.\\.(/|$)"))
    message(FATAL_ERROR "iterm_census: ${where}: ${key} does not have the form ${re}: '${value}'")
  endif()
endfunction()

function(iterm_census)
  cmake_parse_arguments(A "" "SETTINGS;SOURCE_DIR;PROJECT;SDK;RECIPES;METADATA_DIR;LIST_FILE" "" ${ARGN})
  if(A_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "iterm_census: unexpected arguments: ${A_UNPARSED_ARGUMENTS}")
  endif()
  foreach(k SETTINGS SOURCE_DIR SDK RECIPES METADATA_DIR LIST_FILE)
    if(NOT IS_ABSOLUTE "${A_${k}}")
      message(FATAL_ERROR "iterm_census: ${k} must be an absolute path (got '${A_${k}}')")
    endif()
  endforeach()
  if(NOT EXISTS "${A_SETTINGS}")
    message(FATAL_ERROR "iterm_census: no settings file ${A_SETTINGS}")
  endif()
  if(NOT "${A_PROJECT}" MATCHES "^[A-Za-z0-9_.+-]+\\.xcodeproj$" OR NOT EXISTS "${A_SOURCE_DIR}/${A_PROJECT}/project.pbxproj")
    message(FATAL_ERROR "iterm_census: ${A_SOURCE_DIR} has no project ${A_PROJECT}")
  endif()

  file(STRINGS "${A_SETTINGS}" lines)
  set(n 0)
  set(lineno 0)
  foreach(line IN LISTS lines)
    math(EXPR lineno "${lineno} + 1")
    if(line MATCHES "^[ \t]*(#.*)?$")
      continue()
    endif()
    if(NOT line MATCHES "^([A-Z_]+)=(.*)$")
      message(FATAL_ERROR "iterm_census: ${A_SETTINGS}:${lineno} is not KEY=VALUE: ${line}")
    endif()
    set(key "${CMAKE_MATCH_1}")
    set(value "${CMAKE_MATCH_2}")
    if(NOT key IN_LIST _ITERM_CENSUS_KEYS)
      message(FATAL_ERROR "iterm_census: ${A_SETTINGS}:${lineno}: unknown key ${key}")
    endif()
    if(key STREQUAL "TARGET")
      math(EXPR n "${n} + 1")
    elseif(n EQUAL 0)
      message(FATAL_ERROR "iterm_census: ${A_SETTINGS}:${lineno}: ${key} before any TARGET=")
    endif()
    if(DEFINED B${n}_${key})
      message(FATAL_ERROR "iterm_census: ${A_SETTINGS}:${lineno}: ${key} repeated in one block")
    endif()
    _iterm_census_check("${key}" "${value}" "${A_SETTINGS}:${lineno}")
    set(B${n}_${key} "${value}")
  endforeach()
  if(n EQUAL 0)
    message(FATAL_ERROR "iterm_census: ${A_SETTINGS} names no TARGET")
  endif()

  file(READ "${A_SOURCE_DIR}/${A_PROJECT}/project.pbxproj" pbxproj)
  set(targets "")
  set(prefixes "")
  foreach(i RANGE 1 ${n})
    foreach(k IN LISTS _ITERM_CENSUS_KEYS)
      if(NOT DEFINED B${i}_${k})
        message(FATAL_ERROR "iterm_census: ${A_SETTINGS}: target ${B${i}_TARGET} has no ${k}=")
      endif()
    endforeach()
    # platform: Xcode writes a target's object over many lines; it holds lists ( ) but no braces, so
    #           [^}]* stays inside one object whichever layout the file uses
    string(REGEX REPLACE "([.+])" "\\\\\\1" name_re "${B${i}_TARGET}")
    string(REGEX MATCH "isa = PBXNativeTarget;[^}]*[ \t\n]name = (\"${name_re}\"|${name_re});" named "${pbxproj}")
    if(NOT named)
      message(FATAL_ERROR "iterm_census: ${A_PROJECT} has no target named ${B${i}_TARGET}")
    endif()
    list(APPEND targets "${B${i}_TARGET}")
    list(APPEND prefixes "${B${i}_PREFIX}")
  endforeach()

  mavericks_export_xcode_sources(sources_file
    PROJECT "${A_SOURCE_DIR}/${A_PROJECT}"
    TARGETS ${targets}
    PREFIXES ${prefixes}
    HOST_COMPILER "${ITERM_CLANG22_COMPILER}"
    OUTPUT_DIR "${CMAKE_BINARY_DIR}/xcode-inputs")
  include("${sources_file}")

  set(listing "")
  foreach(i RANGE 1 ${n})
    set(P "${B${i}_PREFIX}")
    set(t "census_${P}")
    set(srcs "")
    foreach(s IN LISTS ${P}_SOURCES)
      if(NOT EXISTS "${A_SOURCE_DIR}/${s}")
        message(FATAL_ERROR "iterm_census: ${B${i}_TARGET} lists ${s}, which ${A_SOURCE_DIR} does not have")
      endif()
      list(APPEND srcs "${A_SOURCE_DIR}/${s}")
    endforeach()
    if(NOT srcs)
      message(FATAL_ERROR "iterm_census: the export lists no sources for ${B${i}_TARGET}")
    endif()
    string(APPEND listing "${P}\t${B${i}_TARGET}\n")
    add_library(${t} OBJECT ${srcs})
    set_target_properties(${t} PROPERTIES
      C_STANDARD ${B${i}_C_STANDARD} C_EXTENSIONS ${B${i}_C_EXTENSIONS}
      OBJC_STANDARD ${B${i}_C_STANDARD} OBJC_EXTENSIONS ${B${i}_C_EXTENSIONS})
    target_compile_options(${t} PRIVATE -O0 -ferror-limit=0)
    if(B${i}_ARC)
      target_compile_options(${t} PRIVATE "$<$<COMPILE_LANGUAGE:OBJC,OBJCXX>:-fobjc-arc>")
    endif()
    if(NOT B${i}_PREFIX_HEADER STREQUAL "")
      if(NOT EXISTS "${A_SOURCE_DIR}/${B${i}_PREFIX_HEADER}")
        message(FATAL_ERROR "iterm_census: ${B${i}_TARGET}'s prefix header ${B${i}_PREFIX_HEADER} is not in ${A_SOURCE_DIR}")
      endif()
      target_compile_options(${t} PRIVATE "SHELL:-include ${A_SOURCE_DIR}/${B${i}_PREFIX_HEADER}")
    endif()
    string(REPLACE " " ";" incs_rel "${B${i}_INCLUDES}")
    set(incs "")
    foreach(d IN LISTS incs_rel ${P}_INCLUDE_DIRS)
      if(d STREQUAL ".")
        list(APPEND incs "${A_SOURCE_DIR}")
      elseif(NOT d STREQUAL "")
        list(APPEND incs "${A_SOURCE_DIR}/${d}")
      endif()
    endforeach()
    if(incs)
      target_include_directories(${t} PRIVATE ${incs})
    endif()
    if(NOT B${i}_DEFINES STREQUAL "")
      string(REPLACE " " ";" defs "${B${i}_DEFINES}")
      target_compile_definitions(${t} PRIVATE ${defs})
    endif()
    if(B${i}_METADATA)
      mavericks_target_sdk_metadata(TARGET ${t} SDK "${A_SDK}" RECIPES "${A_RECIPES}"
                                    IDS ${ITERM_METADATA_IDS} OUTPUT_DIR "${A_METADATA_DIR}")
    endif()
  endforeach()
  file(WRITE "${A_LIST_FILE}" "${listing}")
endfunction()
