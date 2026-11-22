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
