# How Mavericks iTerm2 builds

iTerm2 3.0.15 builds for Mac OS X 10.9 (x86_64, minimum 10.9, the pinned 10.9 SDK) without Xcode at any stage: natively on 10.9, or cross on a modern Mac, from the same pinned inputs. Each section below is the decision a script or CMake module cites.

## Inputs

`build/prepare-inputs.sh OUTPUT_ROOT` turns the pins into verified inputs, and writes `OUTPUT_ROOT/inputs.cmake` and `inputs.json` only when everything verifies:

- the iTerm2 source at `components/iterm2/version` (a release tag, its commit and the SHA-256 of GitHub's tarball of it), fetched fresh by shipyard's `fetch_pinned_source.sh` and patched with `patches/*.patch` through `apply_patches.sh`;
- upstream's release ZIP at `components/iterm2-resources/version`, for its compiled resources (see "Resources and the bundle");
- `UPSTREAM_VERSION`, which must agree with the source tag and the ZIP's version;
- shipyard's released modules (`MavericksSDKMetadata`, `MavericksXcodeInputs`, `MavericksResourceInputs`, `MavericksHostTools`), clang22 (`clang22` on 10.9, `clang22-cross` on a modern Mac) and Recaulk, each installed at exactly its pin.

Pin files are data: each value must match its pattern, and none is evaluated. A failure leaves no inputs file behind. The outputs live outside the checkout.

Configure receives `inputs.cmake` as `ITERM_INPUTS_FILE` (the presets set it). `cmake/ITermInputs.cmake` reads it before `project()` and selects its clang22 for C and Objective-C, refusing any other compiler; after `project()` the detected compiler must be the pinned clang22's version. Apple clang on 10.9 cannot parse the sources' Objective-C generics, so `MAVERICKS_REQUIRE_APPLECLANG` is off; the mode, SDK and compatibility gates stay.

## Targets

shipyard's `mavericks_export_xcode_sources` lists each target's sources from the pinned `iTerm2.xcodeproj`. The exporter does not carry ARC, prefix headers or the link graph faithfully, so `cmake/ITermTargets.cmake` applies one explicit row per target, copied from that target's Deployment configuration: iTerm2 (the app), iTerm2Shared and SSKeychain (static libraries) and image_decoder (a helper). Unknown row keys and unknown exported variables are refused, never dropped. Core Data models are not compiled: the release's compiled model is used.

The 10.9 SDK lacks declarations the sources use (Objective-C lightweight generics, among others). Recaulk ships them as SDK-metadata recipes; `mavericks_target_sdk_metadata` gives the targets that opt in a VFS overlay of the edited headers, and never changes the SDK. The recipe ids are in `cmake/ITermMetadata.cmake`.

`patches/0001` makes image_decoder's two casts to CF types `__bridge`, so clang22 accepts them under ARC.

## Dependency dispositions

`components/dependencies.tsv` names each framework the pinned release links or embeds, and what this build does with it:

- **ColorPicker** is rebuilt from the source in the pinned archive (`ColorPicker/`, LGPL 2.1) by `cmake/ITermColorPicker.cmake`: an x86_64 framework, version A, install name `@rpath/ColorPicker.framework/Versions/A/ColorPicker`, at the 10.9 floor. The prebuilt framework, ColorPickerDemo and ColorPickerTests are never inputs.
- **Growl** is dropped: it is defunct, and the prebuilt framework's source and license are unidentified. `patches/0002` delivers notifications through `NSUserNotificationCenter`, keeping every class, selector and stored name.
- **NMSSH** is dropped: its prebuilt framework carries libssh2 1.7.0 (CVE-2019-3855) and OpenSSL 1.0.2g. `patches/0003` makes every scp transfer fail visibly, with the reason.
- **Sparkle** (the old embedded engine) is dropped; see "Updates".

No Growl, NMSSH, libssh2 or Sparkle file, load command or symbol may reach the app.

## Updates

The family updater, not an embedded Sparkle, checks for and installs updates. `patches/0004` removes every use of Sparkle. Check for Updates launches the family updater with `--user`, which always shows its window. Its bundle id comes only from shipyard's product registry (`product-name.sh updater-bundle-id iterm2`), as `ITERM_UPDATER_BUNDLE_ID`; the release page comes from the registered repository, as `ITERM_RELEASES_URL`. A missing updater, or one that cannot be opened, is explained in an alert.

Upstream's compiled MainMenu.nib instantiates a class named `SUUpdater` as Check for Updates' target. This build has no nib compiler, and editing the XIB would break the pairing with the compiled nib, so `product/SUUpdater.m` defines that class with only `checkForUpdates:`, which forwards to the app delegate. `product/iTermFamilyVersion.m` keeps the version ordering iTerm2's incompatible-software checks took from Sparkle.

## Resources and the bundle

The 29 nibs and the compiled Core Data model come from the release ZIP (`resources/compiled.tsv`, each at its measured size and SHA-256), staged by shipyard's `mavericks_extract_resource_members`, which also checks the ZIP's own version. Every other resource is copied from the pinned source as `resources/app-resources.tsv` lists. `resources/source-contract.json` records what is verified about the source-to-nib pairing and what is not.

`build/assemble-bundle.sh` builds `iTerm2.app` from those inputs, the rebuilt executables and ColorPicker: image_decoder in `Contents/Resources` (where iTerm2 finds it with `pathForResource`), mode 0755, beside its sandbox profile; `iTerm2.icns` made by `iconutil` from the asset catalog's AppIcon (a catalog with anything more is refused, since there is no `actool`); the PNG pairs as they are, which `NSImage` resolves by name; and upstream's Info.plist with this product's identity (`dev.mavergreen.iterm2.app`, Mavericks iTerm2), its `<upstream>-mavericks.N` version and that version's comparison key, the 10.9 floor and no Sparkle keys. `build/check-bundle.sh` refuses any bundle that differs from these inputs, including any extra executable and any binary it cannot read.

## Build evidence

`build/record-build.sh BUILD_DIR EVIDENCE_DIR` builds the app, keeps the whole log and the real exit status, and writes `findings.json`: PASS only for a complete build whose output exists, passes shipyard's compat guard and leaves the checkout unchanged; BLOCKED otherwise. It records the host, mode, compiler and its version, shipyard's version, the declared inputs and the output's inventory. A leg that was not run is recorded with `--absent` as ABSENT, with its reason. Runtime behavior is never measured here: it stays UNMEASURED until a separately authorized acceptance run.

A normal build stops at the first failed target and skips everything that depends on it. `build/sweep.sh BUILD_DIR OUT_DIR` measures every unit anyway: it syntax-checks each entry of `compile_commands.json` (the presets export it) and writes every error to `errors.tsv`. It is a diagnostic, never the verdict. While declaration fixes are iterated, `-DITERM_UNRELEASED_RECIPES=<path>` builds against a Recaulk working tree's recipes; the build records it, and `record-build.sh` reports such a build BLOCKED, naming the recipes, however it builds. The setting stays in the build directory's cache, so a reconfigure that leaves it out still builds against them; `-UITERM_UNRELEASED_RECIPES` returns to the pinned recipes.

## Security advisories

`SECURITY.md` and `security/advisories.tsv` record every published iTerm2 advisory against the pinned source: fixed by a patch, guarded by a check 3.0.15 already has, absent because 3.0.15 lacks the feature, or pending. `tests/advisories-test.sh` prepares the source and fails, naming the advisory, when an absent feature appears, a guard disappears or a fix's patch is no longer applied, so moving to a newer upstream cannot bring an advisory back unnoticed.

## Building a commit on another host

Take committed state with `git archive`, never a shared work tree, and give each extract its own directory name (`mavergreen-iterm2-<commit>`). The presets name the build directory after the source directory under `$TMPDIR/mm-build` and do not take a caller's build root, so two extracts with the same name would share one; `-B <dir>` on the configure also separates them.
