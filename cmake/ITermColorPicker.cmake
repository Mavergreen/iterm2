# ITermColorPicker.cmake -- ColorPicker.framework, rebuilt from the pinned archive's ColorPicker/ project.
#
# iterm_add_colorpicker(SOURCES_FILE <abs> SOURCE_DIR <abs ColorPicker project directory>
#                       SDK <abs> RECIPES <abs> METADATA_DIR <abs>)
#   SOURCES_FILE is what mavericks_export_xcode_sources wrote for ColorPicker.xcodeproj's ColorPicker
#   target with prefix COLORPICKER. Defines the target ColorPicker: an x86_64 framework, version A,
#   install name @rpath/ColorPicker.framework/Versions/A/ColorPicker, ARC on, gnu99, at the build's
#   own deployment target (10.9), not upstream's 10.8. A path into the prebuilt ColorPicker.framework,
#   ColorPickerDemo or ColorPickerTests, or a variable this module does not apply, is refused. Its
#   images and colors.txt (COLORPICKER_RESOURCES) go into the framework's Resources. Its Objective-C
#   gets the Recaulk SDK-metadata overlay (ITERM_METADATA_IDS), as iTerm2Shared does: it uses NSArray generics.
# iterm_link_colorpicker(<target>...)
#   Links each target to ColorPicker; an executable finds it in @executable_path/../Frameworks.
#
# spec: BUILD.md "Dependency dispositions" -- ColorPicker is rebuilt from source (LGPL 2.1), never
#       copied prebuilt. Settings: ColorPicker.xcodeproj, target ColorPicker, Release configuration.
# platform: the framework's Info.plist is not upstream's ColorPicker/Info.plist, which uses Xcode's
#           $(...) build-setting substitutions; CMake writes its own from MACOSX_FRAMEWORK_IDENTIFIER, and
#           bundle assembly (BUILD.md "Resources and the bundle") owns the shipped plists.

include("${CMAKE_CURRENT_LIST_DIR}/ITermMetadata.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/ITermSourcePrefix.cmake")
function(iterm_add_colorpicker)
  cmake_parse_arguments(A "" "SOURCES_FILE;SOURCE_DIR;SDK;RECIPES;METADATA_DIR" "" ${ARGN})
  if(A_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "iterm_add_colorpicker: unexpected arguments: ${A_UNPARSED_ARGUMENTS}")
  endif()
  foreach(k SOURCES_FILE SOURCE_DIR SDK RECIPES METADATA_DIR)
    if(NOT IS_ABSOLUTE "${A_${k}}")
      message(FATAL_ERROR "iterm_add_colorpicker: ${k} must be an absolute path (got '${A_${k}}')")
    endif()
  endforeach()
  get_cmake_property(before VARIABLES)
  include("${A_SOURCES_FILE}")
  get_cmake_property(after VARIABLES)
  foreach(v IN LISTS after)
    if(v IN_LIST before OR v STREQUAL "before")
      continue()
    endif()
    if(NOT v MATCHES "^COLORPICKER_(SOURCES|MODELS|INCLUDE_DIRS|[A-Z_]*HEADERS|[A-Z_]*RESOURCES)$")
      message(FATAL_ERROR "iterm_add_colorpicker: ${A_SOURCES_FILE} defines ${v}, which this build does not apply")
    endif()
    foreach(p IN LISTS ${v})
      if(p MATCHES "^(ColorPicker\\.framework|ColorPickerDemo|ColorPickerTests)(/|$)")
        message(FATAL_ERROR "iterm_add_colorpicker: ${v} names ${p}; only the ColorPicker target's own sources are inputs")
      endif()
    endforeach()
  endforeach()
  if(NOT COLORPICKER_SOURCES)
    message(FATAL_ERROR "iterm_add_colorpicker: ${A_SOURCES_FILE} lists no COLORPICKER_SOURCES")
  endif()
  set(srcs "")
  foreach(s IN LISTS COLORPICKER_SOURCES)
    list(APPEND srcs "${A_SOURCE_DIR}/${s}")
  endforeach()
  set(public "")
  foreach(h IN LISTS COLORPICKER_PUBLIC_HEADERS)
    list(APPEND public "${A_SOURCE_DIR}/${h}")
  endforeach()
  set(resources "")
  foreach(r IN LISTS COLORPICKER_RESOURCES)
    list(APPEND resources "${A_SOURCE_DIR}/${r}")
  endforeach()
  add_library(ColorPicker SHARED ${srcs} ${public} ${resources})
  set_target_properties(ColorPicker PROPERTIES
    FRAMEWORK TRUE
    FRAMEWORK_VERSION A
    OUTPUT_NAME ColorPicker
    INSTALL_NAME_DIR @rpath
    BUILD_WITH_INSTALL_NAME_DIR ON
    PUBLIC_HEADER "${public}"
    RESOURCE "${resources}"
    MACOSX_FRAMEWORK_IDENTIFIER com.googlecode.iterm2.ColorPicker
    C_STANDARD 99 C_EXTENSIONS ON OBJC_STANDARD 99 OBJC_EXTENSIONS ON)
  target_compile_options(ColorPicker PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
  iterm_map_source_prefix(ColorPicker "${A_SOURCE_DIR}" ColorPicker)
  target_link_libraries(ColorPicker PRIVATE "-framework AppKit")
  # spec: BUILD.md "Build evidence" -- linkers find <ColorPicker/...> in the source too, so a unit that uses
  #       ColorPicker compiles (and is swept) even before the framework's Headers are copied
  target_include_directories(ColorPicker INTERFACE "${A_SOURCE_DIR}")
  mavericks_target_sdk_metadata(TARGET ColorPicker SDK "${A_SDK}" RECIPES "${A_RECIPES}"
                                IDS ${ITERM_METADATA_IDS} OUTPUT_DIR "${A_METADATA_DIR}")
endfunction()

function(iterm_link_colorpicker)
  foreach(t IN LISTS ARGN)
    target_link_libraries(${t} PRIVATE ColorPicker)
    get_target_property(type ${t} TYPE)
    if(type STREQUAL "EXECUTABLE")
      # platform: CMake adds the build tree's directories to an executable's run paths unless it links
      #           with the install run path, and assemble-bundle.sh ships the linked executable as it is
      set_target_properties(${t} PROPERTIES
        BUILD_WITH_INSTALL_RPATH ON
        INSTALL_RPATH "@executable_path/../Frameworks")
    endif()
  endforeach()
endfunction()
