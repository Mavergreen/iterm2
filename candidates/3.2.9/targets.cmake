# candidates/3.2.9/targets.cmake -- iTerm2 3.2.9's app-target closure (iTerm2, iTerm2Shared, iTerm2SharedARC,
# SSKeychain, image_decoder), one row per target from its Deployment configuration in the v3.2.9
# iTerm2.xcodeproj (target level, else project level).
# spec: BUILD.md "Targets" -- the row keys are documented in cmake/ITermTargets.cmake
# spec: candidates/README.md -- what this table does not yet carry, and which plan adds it:
#   PRODUCT_SOURCES and UPDATER_ID come with patch 0004's port (Milestone C plan 2); -lc++, the link order
#   of the two shared libraries and any WEAK_CLASSES are settled when the candidate first links (plan 1,
#   Task 5); NMSSH, Sparkle and ColorPicker are linked or dropped as in 3.0.15 (BUILD.md "Dependency
#   dispositions").
set(ITERM_LANGUAGES C OBJC CXX OBJCXX)
# The Recaulk SDK-metadata recipes (cmake/ITermMetadata.cmake): 3.0.15's, with the v2 recipes Recaulk
# 20261122.5 made for 3.2.9 in place of their v1 (appkit-event-v2 includes appkit-event-stage-v1), and the new ones.
# Not yet selected: foundation-filemanager-keys-v1 and appkit-viewcontroller-lifecycle-v1 each edit a header that
# foundation-directoryenumerator-generics-v1 or appkit-titlebar-accessory-v1 already edits (shipyard refuses two
# recipes on one header); they wait for Recaulk's combined recipes.
set(ITERM_METADATA_IDS
  foundation-array-generics-v2
  foundation-dictionary-generics-v1
  foundation-set-generics-v1
  foundation-orderedset-generics-v1
  foundation-maptable-generics-v1
  foundation-enumerator-generics-v1
  foundation-directoryenumerator-generics-v1
  foundation-objcruntime-macros-v2
  foundation-rectedge-v1
  appkit-view-properties-v1
  appkit-control-properties-v1
  appkit-cell-properties-v2
  appkit-textfield-properties-v1
  appkit-windowcontroller-properties-v1
  appkit-event-v2
  appkit-window-v2
  appkit-titlebar-accessory-v1
  appkit-searchfield-delegate-v1
  appkit-textalignment-v1
  webkit-wkwebview-v1
  launchservices-default-app-v2
  corefoundation-availability-v1
  appkit-compositing-v1
  appkit-alert-style-v1
  appkit-buttoncell-names-v1
  appkit-accessibility-protocols-v1
  foundation-filecoordinator-v1
  foundation-string-contains-v1)
# Drivers only this upstream builds, each tests/drivers/<name>-driver.m.
set(ITERM_TABLE_DRIVERS metal-unavailable)
set(ITERM_TARGETS iTerm2 iTerm2Shared iTerm2SharedARC SSKeychain image_decoder)
set(ITERM_ROW_iTerm2
  KIND executable  EXPORT_PREFIX ITERM2  ARC OFF  PREFIX_HEADER ""
  C_STANDARD 99  C_EXTENSIONS OFF  OPTIMIZATION 3  INCLUDES sources/proto . ThirdParty
  LINK iTerm2Shared iTerm2SharedARC
  FRAMEWORKS IOKit OpenDirectory Security ScriptingBridge AppKit Carbon Quartz
  SDK_LIBS aprutil-1 icucore ncurses  LINK_OPTIONS -ObjC  DEPENDS image_decoder  METADATA ON  OBJC_WEAK ON
  DEFINES ITERM_NO_METAL)
set(ITERM_ROW_iTerm2Shared
  KIND static  EXPORT_PREFIX ITERM2_SHARED  ARC OFF  PREFIX_HEADER sources/iTerm2.pch
  C_STANDARD 99  C_EXTENSIONS ON  OPTIMIZATION s  INCLUDES sources/proto ThirdParty sources/Metal/Support
  LINK SSKeychain  FRAMEWORKS Cocoa  METADATA ON  OBJC_WEAK ON  CXX_STANDARD gnu++11
  DEFINES ITERM_NO_METAL)
set(ITERM_ROW_iTerm2SharedARC
  KIND static  EXPORT_PREFIX ITERM2_SHARED_ARC  ARC ON  PREFIX_HEADER sources/iTerm2.pch
  C_STANDARD 99  C_EXTENSIONS ON  OPTIMIZATION s  INCLUDES sources/proto ThirdParty
  METADATA ON  CXX_STANDARD gnu++11
  DEFINES ITERM_NO_METAL
  # platform: 10.9 has no Metal; the renderer is left out and the legacy renderer always draws (patch 0013)
  EXCLUDE_SOURCES
    sources/Metal/Infrastructure/iTermASCIITexture.m
    sources/Metal/Infrastructure/iTermCharacterBitmap.m
    sources/Metal/Infrastructure/iTermCharacterParts.m
    sources/Metal/Infrastructure/iTermData.m
    sources/Metal/Infrastructure/iTermMetalCellRenderer.m
    sources/Metal/Infrastructure/iTermMetalDebugInfo.m
    sources/Metal/Infrastructure/iTermMetalRenderer.m
    sources/Metal/Infrastructure/iTermMetalRowData.m
    sources/Metal/Infrastructure/iTermSubpixelModelBuilder.mm
    sources/Metal/Infrastructure/iTermTexture.m
    sources/Metal/Infrastructure/iTermTextureArray.m
    sources/Metal/Infrastructure/iTermTexturePool.m
    sources/Metal/Renderers/iTermBackgroundColorRenderer.mm
    sources/Metal/Renderers/iTermBackgroundImageRenderer.m
    sources/Metal/Renderers/iTermBadgeRenderer.m
    sources/Metal/Renderers/iTermBroadcastStripesRenderer.m
    sources/Metal/Renderers/iTermCopyBackgroundRenderer.m
    sources/Metal/Renderers/iTermCursorGuideRenderer.m
    sources/Metal/Renderers/iTermCursorRenderer.m
    sources/Metal/Renderers/iTermFullScreenFlashRenderer.m
    sources/Metal/Renderers/iTermHighlightRowRenderer.mm
    sources/Metal/Renderers/iTermImageRenderer.m
    sources/Metal/Renderers/iTermIndicatorRenderer.m
    sources/Metal/Renderers/iTermMarginRenderer.m
    sources/Metal/Renderers/iTermMarkRenderer.m
    sources/Metal/Renderers/iTermTextRenderer.mm
    sources/Metal/Renderers/iTermTextRendererTransientState.mm
    sources/Metal/Renderers/iTermTexturePageCollection.mm
    sources/Metal/Renderers/iTermTimestampsRenderer.m
    sources/Metal/Support/iTermCharacterSource.m
    sources/Metal/iTermMetalDriver.m
    sources/iTermMetalBufferPool.m
    sources/iTermMetalFrameData.m
    sources/iTermMetalGlue.m
    sources/iTermMetalPerFrameState.m
    sources/iTermMetalPerFrameStateConfiguration.m
    sources/iTermMetalPerFrameStateRow.m
)
set(ITERM_ROW_SSKeychain
  KIND static  EXPORT_PREFIX SSKEYCHAIN  ARC ON  PREFIX_HEADER ThirdParty/SSKeychain/SSKeychain-Prefix.pch
  C_STANDARD 99  C_EXTENSIONS ON  OPTIMIZATION s  FRAMEWORKS Cocoa  METADATA OFF  CXX_STANDARD gnu++11)
set(ITERM_ROW_image_decoder
  KIND executable  EXPORT_PREFIX IMAGE_DECODER  ARC ON  PREFIX_HEADER ""
  C_STANDARD 99  C_EXTENSIONS ON  OPTIMIZATION s  FRAMEWORKS Cocoa ApplicationServices
  SDK_LIBS aprutil-1  METADATA ON  CXX_STANDARD gnu++11)
