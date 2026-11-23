# cmake/targets/3.0.15.cmake -- the four production targets of iTerm2 3.0.15 (the shipping upstream): one
# row per target, copied from that target's Deployment configuration in the pinned iTerm2.xcodeproj.
# spec: BUILD.md "Targets" -- the row keys are documented in cmake/ITermTargets.cmake
set(ITERM_LANGUAGES C OBJC)
# The Recaulk SDK-metadata recipes (cmake/ITermMetadata.cmake).
set(ITERM_METADATA_IDS
  foundation-array-generics-v2
  foundation-dictionary-generics-v1
  foundation-set-generics-v1
  foundation-orderedset-generics-v1
  foundation-maptable-generics-v1
  foundation-enumerator-generics-v1
  foundation-directoryenumerator-generics-v1
  foundation-objcruntime-macros-v1
  foundation-rectedge-v1
  appkit-view-properties-v1
  appkit-control-properties-v1
  appkit-cell-properties-v1
  appkit-textfield-properties-v1
  appkit-windowcontroller-properties-v1
  appkit-event-stage-v1
  appkit-window-v1
  appkit-titlebar-accessory-v1
  appkit-searchfield-delegate-v1
  appkit-textalignment-v1
  webkit-wkwebview-v1
  launchservices-default-app-v2)
set(ITERM_TARGETS iTerm2 iTerm2Shared SSKeychain image_decoder)
set(ITERM_ROW_iTerm2
  KIND executable  EXPORT_PREFIX ITERM2  ARC OFF  PREFIX_HEADER ""
  C_STANDARD 99  C_EXTENSIONS OFF  OPTIMIZATION 3  INCLUDES . ThirdParty
  LINK iTerm2Shared
  FRAMEWORKS OpenDirectory Security ScriptingBridge AppKit Carbon Quartz
  SDK_LIBS aprutil-1 icucore ncurses  LINK_OPTIONS -ObjC  DEPENDS image_decoder  METADATA ON
  WEAK_CLASSES NSTitlebarAccessoryViewController
  PRODUCT_SOURCES SUUpdater.m iTermFamilyVersion.m)
set(ITERM_ROW_iTerm2Shared
  KIND static  EXPORT_PREFIX ITERM2_SHARED  ARC OFF  PREFIX_HEADER sources/iTerm2.pch
  C_STANDARD 99  C_EXTENSIONS ON  OPTIMIZATION s
  LINK SSKeychain  FRAMEWORKS Cocoa  METADATA ON  UPDATER_ID ON
  PRODUCT_SOURCES iTermFamilyUpdaterPreferences.m)
set(ITERM_ROW_SSKeychain
  KIND static  EXPORT_PREFIX SSKEYCHAIN  ARC ON  PREFIX_HEADER ThirdParty/SSKeychain/SSKeychain-Prefix.pch
  C_STANDARD 99  C_EXTENSIONS ON  OPTIMIZATION s  FRAMEWORKS Cocoa  METADATA OFF)
set(ITERM_ROW_image_decoder
  KIND executable  EXPORT_PREFIX IMAGE_DECODER  ARC ON  PREFIX_HEADER ""
  C_STANDARD 99  C_EXTENSIONS ON  OPTIMIZATION s  FRAMEWORKS Cocoa ApplicationServices
  SDK_LIBS aprutil-1  METADATA ON)

