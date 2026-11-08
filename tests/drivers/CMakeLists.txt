# spec: BUILD.md "Build evidence" -- driver tests: never part of the app, built only by the drivers target,
#       run by record-build.sh on native builds (CTest label "driver").
add_custom_target(drivers)
iterm_add_driver(smoke smoke-driver.m fake-tmux.m)
iterm_add_driver(tmux-control-c tmux-control-c-driver.m fake-tmux.m)
iterm_add_driver(tmux-injection tmux-injection-driver.m fake-tmux.m)
iterm_add_driver(support-directory support-directory-driver.m)
iterm_add_driver(url-command url-command-driver.m)
iterm_add_driver(restart-for-update restart-for-update-driver.m)
iterm_add_driver(updater-preferences updater-preferences-driver.m)
# spec: SMOKE.md check 5 -- a bare executable's main bundle is its own directory, so image_decoder and its
#       sandbox profile go beside the driver, as they sit in the app's Resources
iterm_add_driver(image-decoder image-decoder-driver.m)
add_dependencies(driver-image-decoder image_decoder)
target_compile_definitions(driver-image-decoder PRIVATE "ITERM_DRIVER_PNG=\"${ITERM_SOURCE_DIR}/images/BigArrow.png\"")
add_custom_command(TARGET driver-image-decoder POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_FILE:image_decoder>" "$<TARGET_FILE_DIR:driver-image-decoder>/image_decoder"
  COMMAND "${CMAKE_COMMAND}" -E copy "${ITERM_SOURCE_DIR}/OtherResources/image_decoder.sb"
          "$<TARGET_FILE_DIR:driver-image-decoder>/image_decoder.sb")
