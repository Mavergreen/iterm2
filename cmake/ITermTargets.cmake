# ITermTargets.cmake -- the four production targets of iTerm2 3.0.15, from the exported source lists.
#
# iterm_add_targets(SOURCES_FILE <abs> SOURCE_DIR <abs> SDK <abs> RECIPES <abs> METADATA_DIR <abs>
#                   UPDATER_BUNDLE_ID <id> RELEASES_URL <https url> PRODUCT_DIR <abs>)
#   SOURCES_FILE is what mavericks_export_xcode_sources wrote: per target, <P>_SOURCES (code),
#   <P>_MODELS (Core Data models, never compiled; the release's compiled model is a resource), and
#   <P>_INCLUDE_DIRS, <P>_*HEADERS, <P>_*RESOURCES. Any other variable it defines is refused, never
#   dropped. Each target's settings are one row below, copied from that target's Deployment
#   configuration in the pinned iTerm2.xcodeproj (and the project-level row where the target sets
#   none); an unknown key in a row is refused.
#
# spec: BUILD.md "Targets" -- an explicit per-target table, not the exporter's generated build.
# spec: BUILD.md "Dependency dispositions" -- Growl, NMSSH and Sparkle are never linked.
#
# Row keys:
#   KIND           static | executable
#   EXPORT_PREFIX  the exporter's variable prefix for this target
#   ARC            ON | OFF (CLANG_ENABLE_OBJC_ARC; unset in the project means OFF)
#   PREFIX_HEADER  GCC_PREFIX_HEADER, relative to SOURCE_DIR, or empty
#   C_STANDARD     GCC_C_LANGUAGE_STANDARD: 99 with C_EXTENSIONS ON for gnu99, OFF for c99
#   C_EXTENSIONS   ON | OFF
#   INCLUDES       HEADER_SEARCH_PATHS, relative to SOURCE_DIR
#   LINK           in-tree targets linked directly (Xcode's libiTerm2Shared.a / libSSKeychain.a)
#   FRAMEWORKS     SDK frameworks linked
#   SDK_LIBS       SDK dylibs linked as <SDK>/usr/lib/lib<name>.dylib -- the pinned SDK's own dylib,
#                  never Xcode's later .tbd reference (libaprutil-1.tbd in the project)
#   LINK_OPTIONS   OTHER_LDFLAGS that are not libraries
#   WEAK_CLASSES   SDK classes newer than 10.9 that a source subclasses: the link allows their class and
#                  metaclass symbols undefined. The 10.9 frameworks do not export them, and the Objective-C
#                  runtime leaves a subclass of a missing class unrealized, so each use must be guarded.
#   DEPENDS        targets built first (Xcode target dependencies that are not links)
#   METADATA       ON | OFF: the Recaulk SDK-metadata overlay for this target's Objective-C
#   PRODUCT_SOURCES this product's own sources, relative to PRODUCT_DIR (product/SUUpdater.m, product/iTermFamilyVersion.m,
#                   product/iTermFamilyUpdaterPreferences.m)
#   UPDATER_ID     ON: compile with ITERM_UPDATER_BUNDLE_ID="<UPDATER_BUNDLE_ID>" and
#                  ITERM_RELEASES_URL="<RELEASES_URL>" (patch 0004's
#                  checkForUpdates: is in iTermApplicationDelegate.m, which iTerm2Shared compiles)
#
# platform: CLANG_ENABLE_MODULES=YES in the project lets Xcode auto-link frameworks from imports; this
#           build does not enable modules (no source uses @import), so each row names its frameworks.
# platform: warning flags are not copied: upstream sets no -Werror, so they change no outcome here.

include("${CMAKE_CURRENT_LIST_DIR}/ITermMetadata.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/ITermSourcePrefix.cmake")
set(ITERM_TARGETS iTerm2 iTerm2Shared SSKeychain image_decoder)
set(ITERM_ROW_iTerm2
  KIND executable  EXPORT_PREFIX ITERM2  ARC OFF  PREFIX_HEADER ""
  C_STANDARD 99  C_EXTENSIONS OFF  INCLUDES . ThirdParty
  LINK iTerm2Shared
  FRAMEWORKS OpenDirectory Security ScriptingBridge AppKit Carbon Quartz
  SDK_LIBS aprutil-1 icucore ncurses  LINK_OPTIONS -ObjC  DEPENDS image_decoder  METADATA ON
  WEAK_CLASSES NSTitlebarAccessoryViewController
  PRODUCT_SOURCES SUUpdater.m iTermFamilyVersion.m)
set(ITERM_ROW_iTerm2Shared
  KIND static  EXPORT_PREFIX ITERM2_SHARED  ARC OFF  PREFIX_HEADER sources/iTerm2.pch
  C_STANDARD 99  C_EXTENSIONS ON
  LINK SSKeychain  FRAMEWORKS Cocoa  METADATA ON  UPDATER_ID ON
  PRODUCT_SOURCES iTermFamilyUpdaterPreferences.m)
set(ITERM_ROW_SSKeychain
  KIND static  EXPORT_PREFIX SSKEYCHAIN  ARC ON  PREFIX_HEADER ThirdParty/SSKeychain/SSKeychain-Prefix.pch
  C_STANDARD 99  C_EXTENSIONS ON  FRAMEWORKS Cocoa  METADATA OFF)
set(ITERM_ROW_image_decoder
  KIND executable  EXPORT_PREFIX IMAGE_DECODER  ARC ON  PREFIX_HEADER ""
  C_STANDARD 99  C_EXTENSIONS ON  FRAMEWORKS Cocoa ApplicationServices
  SDK_LIBS aprutil-1  METADATA ON)

# spec: BUILD.md "Targets" -- the app's system links (frameworks, the SDK's own dylibs, linker options, weak
#       classes), read from the caller's parsed row (R_*), so a driver links exactly as the app does
function(_iterm_link_system t sdk)
  foreach(f IN LISTS R_FRAMEWORKS)
    target_link_libraries(${t} PRIVATE "-framework ${f}")
  endforeach()
  foreach(l IN LISTS R_SDK_LIBS)
    set(lib "${sdk}/usr/lib/lib${l}.dylib")
    if(NOT EXISTS "${lib}")
      message(FATAL_ERROR "${t} links ${lib}, which the pinned SDK does not have")
    endif()
    target_link_libraries(${t} PRIVATE "${lib}")
  endforeach()
  if(R_LINK_OPTIONS)
    target_link_options(${t} PRIVATE ${R_LINK_OPTIONS})
  endif()
  foreach(c IN LISTS R_WEAK_CLASSES)
    target_link_options(${t} PRIVATE "-Wl,-U,_OBJC_CLASS_\$_${c}" "-Wl,-U,_OBJC_METACLASS_\$_${c}")
  endforeach()
endfunction()

# spec: BUILD.md "Build evidence" -- a driver test links the built iTerm2Shared with the app's row and
#       compiles as iTerm2Shared does; it is never built with the app, only by the drivers target
function(iterm_add_driver name)
  cmake_parse_arguments(R "" "KIND;EXPORT_PREFIX;ARC;PREFIX_HEADER;C_STANDARD;C_EXTENSIONS;METADATA;UPDATER_ID"
                        "INCLUDES;LINK;FRAMEWORKS;SDK_LIBS;LINK_OPTIONS;WEAK_CLASSES;DEPENDS;PRODUCT_SOURCES" ${ITERM_ROW_iTerm2})
  set(t driver-${name})
  # platform: -ObjC loads every iTerm2Shared object, and some refer to symbols the app target compiles itself
  #           (its own sources and the product's), so a driver compiles those too, all but main.m
  add_executable(${t} EXCLUDE_FROM_ALL ${ARGN} "$<FILTER:$<TARGET_PROPERTY:iTerm2,SOURCES>,EXCLUDE,/main\\.m$>")
  set_target_properties(${t} PROPERTIES OBJC_STANDARD ${R_C_STANDARD} OBJC_EXTENSIONS ON)
  target_include_directories(${t} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}" "$<TARGET_PROPERTY:iTerm2Shared,INCLUDE_DIRECTORIES>")
  target_compile_options(${t} PRIVATE "$<TARGET_PROPERTY:iTerm2Shared,COMPILE_OPTIONS>")
  # platform: a message to a method the class does not declare is only a warning in Objective-C; a driver
  #           that names one is testing nothing, so it does not build
  target_compile_options(${t} PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-Werror=objc-method-access>")
  target_compile_definitions(${t} PRIVATE "$<TARGET_PROPERTY:iTerm2Shared,COMPILE_DEFINITIONS>")
  target_link_libraries(${t} PRIVATE iTerm2Shared)
  _iterm_link_system(${t} "${CMAKE_OSX_SYSROOT}")
  mavericks_target_sdk_metadata(TARGET ${t} SDK "${CMAKE_OSX_SYSROOT}" RECIPES "${ITERM_RECAULK_RECIPES}"
                                IDS ${ITERM_METADATA_IDS} OUTPUT_DIR "${CMAKE_BINARY_DIR}/sdk-metadata")
  add_dependencies(drivers ${t})
  add_test(NAME driver.${name} COMMAND ${t})
  set_tests_properties(driver.${name} PROPERTIES LABELS driver)
endfunction()

# spec: BUILD.md "Targets" -- the Xcode project is never edited, so a source that a patch deletes is still
#       exported; it is dropped only when some patch under PATCH_DIR deletes exactly that path
function(_iterm_patch_deletes out patch_dir path)
  set(${out} FALSE PARENT_SCOPE)
  if(NOT patch_dir)
    return()
  endif()
  file(GLOB patches "${patch_dir}/*.patch")
  foreach(p IN LISTS patches)
    file(READ "${p}" text)
    string(FIND "${text}" "--- a/${path}\n+++ /dev/null\n" at)
    if(NOT at EQUAL -1)
      set(${out} TRUE PARENT_SCOPE)
      return()
    endif()
  endforeach()
endfunction()

function(iterm_add_targets)
  cmake_parse_arguments(A "" "SOURCES_FILE;SOURCE_DIR;SDK;RECIPES;METADATA_DIR;UPDATER_BUNDLE_ID;RELEASES_URL;PRODUCT_DIR;PATCH_DIR" "" ${ARGN})
  if(A_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "iterm_add_targets: unexpected arguments: ${A_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT "${A_UPDATER_BUNDLE_ID}" MATCHES "^[A-Za-z0-9.-]+$")
    message(FATAL_ERROR "iterm_add_targets: UPDATER_BUNDLE_ID must be a bundle identifier (got '${A_UPDATER_BUNDLE_ID}')")
  endif()
  if(NOT "${A_RELEASES_URL}" MATCHES "^https://[A-Za-z0-9./_-]+$")
    message(FATAL_ERROR "iterm_add_targets: RELEASES_URL must be an https URL (got '${A_RELEASES_URL}')")
  endif()
  foreach(k SOURCES_FILE SOURCE_DIR SDK RECIPES METADATA_DIR PRODUCT_DIR)
    if(NOT IS_ABSOLUTE "${A_${k}}")
      message(FATAL_ERROR "iterm_add_targets: ${k} must be an absolute path (got '${A_${k}}')")
    endif()
  endforeach()

  set(prefixes "")
  foreach(t IN LISTS ITERM_TARGETS)
    cmake_parse_arguments(R "" "KIND;EXPORT_PREFIX;ARC;PREFIX_HEADER;C_STANDARD;C_EXTENSIONS;METADATA;UPDATER_ID"
                          "INCLUDES;LINK;FRAMEWORKS;SDK_LIBS;LINK_OPTIONS;WEAK_CLASSES;DEPENDS;PRODUCT_SOURCES" ${ITERM_ROW_${t}})
    if(R_UNPARSED_ARGUMENTS)
      message(FATAL_ERROR "iterm_add_targets: ${t}'s row has settings this build does not apply: ${R_UNPARSED_ARGUMENTS}")
    endif()
    list(APPEND prefixes "${R_EXPORT_PREFIX}")
  endforeach()
  list(JOIN prefixes "|" prefix_re)

  get_cmake_property(before VARIABLES)
  include("${A_SOURCES_FILE}")
  get_cmake_property(after VARIABLES)
  foreach(v IN LISTS after)
    if(v IN_LIST before OR v STREQUAL "before")
      continue()
    endif()
    if(NOT v MATCHES "^(${prefix_re})_(SOURCES|MODELS|INCLUDE_DIRS|[A-Z_]*HEADERS|[A-Z_]*RESOURCES)$")
      message(FATAL_ERROR "iterm_add_targets: ${A_SOURCES_FILE} defines ${v}, which this build does not apply")
    endif()
  endforeach()

  foreach(t IN LISTS ITERM_TARGETS)
    cmake_parse_arguments(R "" "KIND;EXPORT_PREFIX;ARC;PREFIX_HEADER;C_STANDARD;C_EXTENSIONS;METADATA;UPDATER_ID"
                          "INCLUDES;LINK;FRAMEWORKS;SDK_LIBS;LINK_OPTIONS;WEAK_CLASSES;DEPENDS;PRODUCT_SOURCES" ${ITERM_ROW_${t}})
    set(P "${R_EXPORT_PREFIX}")
    if(NOT ${P}_SOURCES)
      message(FATAL_ERROR "iterm_add_targets: ${A_SOURCES_FILE} lists no ${P}_SOURCES for ${t}")
    endif()
    set(srcs "")
    foreach(s IN LISTS ${P}_SOURCES)
      if(NOT EXISTS "${A_SOURCE_DIR}/${s}")
        _iterm_patch_deletes(deleted "${A_PATCH_DIR}" "${s}")
        if(deleted)
          continue()
        endif()
        message(FATAL_ERROR "iterm_add_targets: ${A_SOURCES_FILE} lists ${s} for ${t}, which ${A_SOURCE_DIR} does not have and no patch deletes")
      endif()
      list(APPEND srcs "${A_SOURCE_DIR}/${s}")
    endforeach()
    foreach(s IN LISTS R_PRODUCT_SOURCES)
      if(NOT EXISTS "${A_PRODUCT_DIR}/${s}")
        message(FATAL_ERROR "iterm_add_targets: ${t}'s product source ${s} is not in ${A_PRODUCT_DIR}")
      endif()
      list(APPEND srcs "${A_PRODUCT_DIR}/${s}")
    endforeach()
    if(R_KIND STREQUAL "static")
      add_library(${t} STATIC ${srcs})
    elseif(R_KIND STREQUAL "executable")
      add_executable(${t} ${srcs})
    else()
      message(FATAL_ERROR "iterm_add_targets: ${t} has KIND '${R_KIND}'")
    endif()
    set_target_properties(${t} PROPERTIES
      C_STANDARD ${R_C_STANDARD} C_EXTENSIONS ${R_C_EXTENSIONS}
      OBJC_STANDARD ${R_C_STANDARD} OBJC_EXTENSIONS ${R_C_EXTENSIONS})
    if(R_UPDATER_ID)
      target_compile_definitions(${t} PRIVATE "ITERM_UPDATER_BUNDLE_ID=\"${A_UPDATER_BUNDLE_ID}\""
                                                "ITERM_RELEASES_URL=\"${A_RELEASES_URL}\"")
    endif()
    if(R_ARC)
      target_compile_options(${t} PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
    endif()
    # platform: __FILE__ (assertions, logging) would otherwise carry the build host's path to the source
    iterm_map_source_prefix(${t} "${A_SOURCE_DIR}" .)
    if(NOT "${R_PREFIX_HEADER}" STREQUAL "")
      if(NOT EXISTS "${A_SOURCE_DIR}/${R_PREFIX_HEADER}")
        message(FATAL_ERROR "iterm_add_targets: ${t}'s prefix header ${R_PREFIX_HEADER} is not in ${A_SOURCE_DIR}")
      endif()
      target_compile_options(${t} PRIVATE "SHELL:-include ${A_SOURCE_DIR}/${R_PREFIX_HEADER}")
    endif()
    set(incs "")
    foreach(i IN LISTS R_INCLUDES ${P}_INCLUDE_DIRS)
      if(i STREQUAL ".")
        list(APPEND incs "${A_SOURCE_DIR}")
      else()
        list(APPEND incs "${A_SOURCE_DIR}/${i}")
      endif()
    endforeach()
    if(incs)
      target_include_directories(${t} PRIVATE ${incs})
    endif()
    foreach(l IN LISTS R_LINK)
      target_link_libraries(${t} PRIVATE ${l})
    endforeach()
    _iterm_link_system(${t} "${A_SDK}")
    foreach(d IN LISTS R_DEPENDS)
      add_dependencies(${t} ${d})
    endforeach()
    if(R_METADATA)
      mavericks_target_sdk_metadata(TARGET ${t} SDK "${A_SDK}" RECIPES "${A_RECIPES}"
                                    IDS ${ITERM_METADATA_IDS} OUTPUT_DIR "${A_METADATA_DIR}")
    endif()
  endforeach()
endfunction()
