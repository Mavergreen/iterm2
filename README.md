<!-- human-review: drafted by an agent; review before publishing. -->
# Mavericks iTerm2

A build of [iTerm2](https://github.com/gnachman/iTerm2) 3.0.15, the last release that supports OS X 10.8 and 10.9, for Mac OS X 10.9 (Mavericks). It builds without Xcode, natively on 10.9 or cross on a modern Mac. It has not been released.

## Build

Install the family's shipyard, clang22 (`clang22-cross` on a modern Mac) and Recaulk at the releases `components/` pins. Then:

```sh
sh build/prepare-inputs.sh "$TMPDIR/mm-build/mavergreen-iterm2-inputs"
shipyard-cmake --preset native        # --preset cross on a modern Mac
shipyard-cmake --build --preset native
```

SECURITY.md lists the iTerm2 security advisories and where each stands.
SMOKE.md is the checklist for running it beside upstream iTerm2 for the first time.

`build/prepare-inputs.sh` fetches and verifies the pinned source and resources, applies `patches/`, and refuses any tool that is not installed at its pin. INGREDIENTS.md lists the inputs; PORT.md the carried changes.

## License

iTerm2 is GPL version 2 (the pinned release's `LICENSE`). ColorPicker is LGPL 2.1.
