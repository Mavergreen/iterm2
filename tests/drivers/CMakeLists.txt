# spec: BUILD.md "Build evidence" -- driver tests: never part of the app, built only by the drivers target,
#       run by record-build.sh on native builds (CTest label "driver").
add_custom_target(drivers)
iterm_add_driver(smoke smoke-driver.m fake-tmux.m)
