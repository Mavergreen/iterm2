# ITermMetadata.cmake -- the Recaulk SDK-metadata recipes every overlaid target in this build uses.
# spec: BUILD.md "Targets" -- Recaulk recipe ids, applied by shipyard's mavericks_target_sdk_metadata. They come
#       with the targets table ITERM_TARGETS_FILE names, as ITERM_METADATA_IDS: each upstream selects its own.
if(NOT IS_ABSOLUTE "${ITERM_TARGETS_FILE}" OR NOT EXISTS "${ITERM_TARGETS_FILE}")
  message(FATAL_ERROR "ITERM_TARGETS_FILE ('${ITERM_TARGETS_FILE}') is not an existing absolute path: prepare the inputs again")
endif()
include("${ITERM_TARGETS_FILE}")
if(NOT ITERM_METADATA_IDS)
  message(FATAL_ERROR "${ITERM_TARGETS_FILE} sets no ITERM_METADATA_IDS (the Recaulk recipes its upstream selects)")
endif()
