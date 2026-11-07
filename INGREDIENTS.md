# Build ingredients

This repository builds iTerm2 3.0.15 for Mac OS X 10.9 (x86_64), natively on 10.9 and cross on a modern Mac, without Xcode. It is a build probe: it has no release workflow and has published nothing.

| Input | Pinned in | Renovate | On a bump |
|---|---|---|---|
| iTerm2 source, release 3.0.15 | `components/iterm2/version`: `REPO`, `REF` (the tag), `DIGEST` (its commit) and the SHA-256 of GitHub's tarball of that commit; `UPSTREAM_VERSION` | `github-tags` on `gnachman/iTerm2`, capped below 3.1 (3.1.0 requires 10.10) | `SHA256`, `UPSTREAM_VERSION` and the resource pin move with it; `build/prepare-inputs.sh` refuses any disagreement, and every patch must still apply without fuzz. |
| Upstream's compiled resources (29 nibs, the Core Data model) | `components/iterm2-resources/version`: the official release ZIP's URL, SHA-256 and `VERSION` | Moves with the source, by hand | `VERSION` must equal `UPSTREAM_VERSION`. Measured hashes of the selected members are in the resource manifest. |
| Framework dispositions | `components/dependencies.tsv` | Not versioned | ColorPicker is rebuilt from the pinned source; Growl, NMSSH and Sparkle are dropped (see PORT.md). |
| Carried patches | `patches/*.patch` | Maintained here | Reasons and retirement conditions are in PORT.md. |
| clang22 (`clang22` on 10.9, `clang22-cross` on a modern Mac), with the Recaulk its `clang.cfg` links | `components/clang22/version` = `22.1.8-mavericks.12` | `github-releases` on `Mavergreen/clang-22` | `build/prepare-inputs.sh` refuses an installed release other than the pin and passes that tree's `clang` to CMake. |
| Recaulk's SDK-metadata recipes | `components/recaulk/version` = `20261107.3`, read from `/usr/local/mavergreen/recaulk/share/sdk-metadata/recipes.json` | `github-releases` on `Mavergreen/recaulk` | Only the recipe data is used from the standalone product; the Recaulk linked into binaries is clang22's own. |
| shipyard: presets, toolchain, the pinned 10.9 SDK, `MavericksSDKMetadata`, `MavericksXcodeInputs`, `MavericksResourceInputs`, `MavericksHostTools`, fetch and patch scripts | the installed shipyard pkg | Untrackable here: shipyard moves by its own releases | `build/prepare-inputs.sh` refuses a shipyard without the four modules. |
