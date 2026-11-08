# ITermResources.cmake -- extracts the release's compiled resources and assembles iTerm2.app.
#
# iterm_add_bundle(SOURCE_DIR <abs> ZIP <abs> ZIP_SHA256 <hex> UPSTREAM_VERSION <v> VERSION <v>-mavericks.N
#                  HOST_COMPILER <abs clang22> OUTPUT_DIR <abs>)
#   At configure time, shipyard's mavericks_extract_resource_members stages exactly resources/compiled.tsv's
#   members of the pinned release ZIP (the 29 nibs and the compiled Core Data model), checking the
#   archive's SHA-256, each member's size and SHA-256, and that the release's Info.plist says
#   UPSTREAM_VERSION. The target iTerm2-app (ALL) then rebuilds <build>/iTerm2.app from scratch with
#   build/assemble-bundle.sh, from iTerm2, image_decoder, the rebuilt ColorPicker and the listed
#   source resources, and refuses it unless build/check-bundle.sh passes.
#
# spec: BUILD.md "Resources and the bundle" -- MEMBER_PREFIX iTerm.app/Contents/Resources/, VERSION_MEMBER
#       iTerm.app/Contents/Info.plist, EXPECT_VERSION the upstream version.
include(MavericksResourceInputs)

function(iterm_add_bundle)
  cmake_parse_arguments(A "" "SOURCE_DIR;ZIP;ZIP_SHA256;UPSTREAM_VERSION;VERSION;HOST_COMPILER;OUTPUT_DIR" "" ${ARGN})
  if(A_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "iterm_add_bundle: unexpected arguments: ${A_UNPARSED_ARGUMENTS}")
  endif()
  set(repo "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/..")
  mavericks_extract_resource_members(compiled
    ARCHIVE "${A_ZIP}"
    SHA256 "${A_ZIP_SHA256}"
    MANIFEST "${repo}/resources/compiled.tsv"
    MEMBER_PREFIX "iTerm.app/Contents/Resources/"
    VERSION_MEMBER "iTerm.app/Contents/Info.plist"
    EXPECT_VERSION "${A_UPSTREAM_VERSION}"
    HOST_COMPILER "${A_HOST_COMPILER}"
    OUTPUT_DIR "${A_OUTPUT_DIR}")
  set(app "${CMAKE_BINARY_DIR}/iTerm2.app")
  add_custom_target(iTerm2-app ALL
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${app}"
    COMMAND sh "${repo}/build/assemble-bundle.sh" "${app}" "${A_SOURCE_DIR}" "${compiled}"
            "$<TARGET_FILE:iTerm2>" "$<TARGET_FILE:image_decoder>" "$<TARGET_BUNDLE_DIR:ColorPicker>" "${A_VERSION}"
            "$<TARGET_FILE:restart-for-update>"
    DEPENDS iTerm2 image_decoder ColorPicker restart-for-update
    COMMENT "Assembling and checking iTerm2.app"
    VERBATIM)
endfunction()
