# Build ingredients

This repository builds iTerm2 3.0.15 for Mac OS X 10.9 (x86_64), natively on 10.9 and cross on a modern Mac, without Xcode, and releases it as `iterm2-<version>.pkg`: the app at `/Applications/Mavericks iTerm2.app` and the family updater.

| Input | Pinned in | Renovate | On a bump |
|---|---|---|---|
| iTerm2 source, release 3.0.15 | `components/iterm2/version`: `REPO`, `REF` (the tag), `DIGEST` (its commit) and the SHA-256 of GitHub's tarball of that commit; `UPSTREAM_VERSION` | `github-tags` on `gnachman/iTerm2`, capped below 3.1 (3.1.0 requires 10.10) | `SHA256`, `UPSTREAM_VERSION` and the resource pin move with it; `build/prepare-inputs.sh` refuses any disagreement, and every patch must still apply without fuzz. |
| Upstream's compiled resources (29 nibs, the Core Data model) | `components/iterm2-resources/version`: the official release ZIP's URL, SHA-256 and `VERSION` | Moves with the source, by hand | `VERSION` must equal `UPSTREAM_VERSION`. Measured hashes of the selected members are in the resource manifest. |
| Framework dispositions | `components/dependencies.tsv` | Not versioned | ColorPicker is rebuilt from the pinned source; Growl, NMSSH and Sparkle are dropped (see PORT.md). |
| Carried patches | `patches/*.patch` | Maintained here | Reasons and retirement conditions are in PORT.md. |
| clang22 (`clang22` on 10.9, `clang22-cross` on a modern Mac), with the Recaulk its `clang.cfg` links | `components/clang22/version` = `22.1.8-mavericks.12` | `github-releases` on `Mavergreen/clang-22` | `build/prepare-inputs.sh` refuses an installed release other than the pin and passes that tree's `clang` to CMake. |
| Recaulk's SDK-metadata recipes | `components/recaulk/version` = `20261108.2`, read from `/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json` | `github-releases` on `Mavergreen/recaulk` | The 21 ids the targets select are `ITERM_METADATA_IDS` in `cmake/ITermMetadata.cmake`; a bump keeps every id, or the sweep (`build/sweep.sh`) shows what a dropped one breaks. Only the recipe data is used from the standalone product; the Recaulk linked into binaries is clang22's own. |
| clang22's Linux archive (collect job only) | `components/clang22/linux-sha256`: that archive's line of the pinned release's `SHA256SUMS` | Moved by hand with the clang22 pin; the clang22 PR says so | `fetch_clang22.sh` verifies the archive whose Mach-O readers check the pkg on Linux. Nothing shipped changes. |
| Longboat (CI only) | `components/longboat/version` | `github-releases`, `YYYYMMDD.N` versioning | CI installs it for the 10.9 SDK that the clang22 pkgs require. Nothing shipped changes; no repackage. |
| shipyard: presets, toolchain, the pinned 10.9 SDK, `MavericksSDKMetadata`, `MavericksXcodeInputs`, `MavericksResourceInputs`, `MavericksHostTools`, fetch and patch scripts | the installed shipyard pkg; in CI, `install@v1`, which also brings Sparkle 1.27.3 for the updater | Untrackable here: shipyard moves by its own releases | `build/prepare-inputs.sh` refuses a shipyard without the four modules. |

## Deviations

- **A weak reference to a post-10.9 class.** iTerm2 subclasses `NSTitlebarAccessoryViewController` (10.10), which 10.9's AppKit does not export, so the iTerm2 row's `WEAK_CLASSES` lets the link leave its class and metaclass symbols undefined (`-Wl,-U`). On 10.9 the Objective-C runtime leaves the subclass unrealized. The source never instantiates it: every use is inside `#if ENABLE_SHORTCUT_ACCESSORY`, which nothing defines. Retire it when Recaulk's recipes name their weak symbols and shipyard's overlay passes them to the link.

## Repackaging

`.github/workflows/repackage-on-ingredient-bump.yml` dispatches a `-mavericks.N+1` repackage when the clang22 or Recaulk pin moves on `main`. The upstream's own pins (`UPSTREAM_VERSION`, `components/iterm2/version`, `components/iterm2-resources/version`) make a new upstream release instead. Longboat and `components/clang22/linux-sha256` change nothing shipped, so they cut nothing.

## Declared state

- upstream: UPSTREAM_VERSION
- source: components/iterm2/version
- resources: components/iterm2-resources/version
- clang22: components/clang22/version
- recaulk: components/recaulk/version

## Conformance deviations

- macos-runner:release.yml:build: the cross build needs clang22-cross, which the family ships only for macOS, with the 10.9 SDK through Longboat; the app's icon is made by iconutil; and shipyard-cmake installs only on macOS. Exit: a Linux-hosted clang22-cross and a Linux icns writer, after which the build runs on Linux.
- on-target:gui: the mavericks-vm guest has no logged-in Aqua session, so the app's windows, Preferences, Notes, notifications and tmux integration are not exercised in CI; the maintainer runs SMOKE.md on each release's own pkg instead. Exit: a GUI session in mavericks-vm, then SMOKE.md automated in vm-test.
