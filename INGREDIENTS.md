# Build ingredients

This repository builds iTerm2 3.0.15 for Mac OS X 10.9 (x86_64), natively on 10.9 and cross on a modern Mac, without Xcode. It is a build probe: it has no release workflow and has published nothing.

| Input | Pinned in | Renovate | On a bump |
|---|---|---|---|
| iTerm2 source, release 3.0.15 | `components/iterm2/version`: `REPO`, `REF` (the tag), `DIGEST` (its commit) and the SHA-256 of GitHub's tarball of that commit; `UPSTREAM_VERSION` | `github-tags` on `gnachman/iTerm2`, capped below 3.1 (3.1.0 requires 10.10) | `SHA256`, `UPSTREAM_VERSION` and the resource pin move with it; `build/prepare-inputs.sh` refuses any disagreement, and every patch must still apply without fuzz. |
| Upstream's compiled resources (29 nibs, the Core Data model) | `components/iterm2-resources/version`: the official release ZIP's URL, SHA-256 and `VERSION` | Moves with the source, by hand | `VERSION` must equal `UPSTREAM_VERSION`. Measured hashes of the selected members are in the resource manifest. |
| Framework dispositions | `components/dependencies.tsv` | Not versioned | ColorPicker is rebuilt from the pinned source; Growl, NMSSH and Sparkle are dropped (see PORT.md). |
| Carried patches | `patches/*.patch` | Maintained here | Reasons and retirement conditions are in PORT.md. |
| clang22 (`clang22` on 10.9, `clang22-cross` on a modern Mac), with the Recaulk its `clang.cfg` links | `components/clang22/version` = `22.1.8-mavericks.12` | `github-releases` on `Mavergreen/clang-22` | `build/prepare-inputs.sh` refuses an installed release other than the pin and passes that tree's `clang` to CMake. |
| Recaulk's SDK-metadata recipes | `components/recaulk/version` = `20261108.2`, read from `/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json` | `github-releases` on `Mavergreen/recaulk` | The 21 ids the targets select are `ITERM_METADATA_IDS` in `cmake/ITermMetadata.cmake`; a bump keeps every id, or the sweep (`build/sweep.sh`) shows what a dropped one breaks. Only the recipe data is used from the standalone product; the Recaulk linked into binaries is clang22's own. |
| shipyard: presets, toolchain, the pinned 10.9 SDK, `MavericksSDKMetadata`, `MavericksXcodeInputs`, `MavericksResourceInputs`, `MavericksHostTools`, fetch and patch scripts | the installed shipyard pkg | Untrackable here: shipyard moves by its own releases | `build/prepare-inputs.sh` refuses a shipyard without the four modules. |

## Deviations

- **A weak reference to a post-10.9 class.** iTerm2 subclasses `NSTitlebarAccessoryViewController` (10.10), which 10.9's AppKit does not export, so the iTerm2 row's `WEAK_CLASSES` lets the link leave its class and metaclass symbols undefined (`-Wl,-U`). On 10.9 the Objective-C runtime leaves the subclass unrealized. The source never instantiates it: every use is inside `#if ENABLE_SHORTCUT_ACCESSORY`, which nothing defines. Retire it when Recaulk's recipes name their weak symbols and shipyard's overlay passes them to the link.
