# spec: BUILD.md "Targets" -- the binaries name their sources relative to the source tree, never by the
#       build host's path
# platform: clang matches the path it was given, which may be the real path or a symlinked one (/var vs
#           /private/var on macOS), so both are mapped
function(iterm_map_source_prefix target dir to)
  file(REAL_PATH "${dir}" real)
  target_compile_options(${target} PRIVATE "-ffile-prefix-map=${dir}=${to}")
  if(NOT real STREQUAL dir)
    target_compile_options(${target} PRIVATE "-ffile-prefix-map=${real}=${to}")
  endif()
endfunction()
