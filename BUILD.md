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

shipyard's `mavericks_export_xcode_sources` lists each target's sources from the pinned `iTerm2.xcodeproj`. The exporter does not carry ARC, prefix headers or the link graph faithfully, so `cmake/ITermTargets.cmake` applies one explicit row per target, copied from that target's Deployment configuration: iTerm2 (the app), iTerm2Shared and SSKeychain (static libraries) and image_decoder (a helper). That includes the optimization level, as upstream shipped it: the app at `-O3`; the others, and ColorPicker (from its Release configuration), at Xcode's default `-Os`, since their configurations set none. CMake's own build type stays unset, so it adds nothing. Unknown row keys and unknown exported variables are refused, never dropped. Core Data models are not compiled: the release's compiled model is used. Every target, ColorPicker included, compiles with `-ffile-prefix-map` from the prepared source to a relative path (`cmake/ITermSourcePrefix.cmake`), so `__FILE__` names a source by its place in the tree, never by the build host's path.

The 10.9 SDK lacks declarations the sources use (Objective-C lightweight generics, among others). Recaulk ships them as SDK-metadata recipes; `mavericks_target_sdk_metadata` gives the targets that opt in a VFS overlay of the edited headers, and never changes the SDK. The recipe ids are in `cmake/ITermMetadata.cmake`. Recipes declare post-10.9 classes and functions weak. 10.9's frameworks do not export them, so a class the app subclasses (`NSTitlebarAccessoryViewController`) is listed as the row's `WEAK_CLASSES`, and the link allows its class and metaclass symbols undefined; the Objective-C runtime leaves the subclass unrealized on 10.9, and the source never instantiates it (every use is inside `#if ENABLE_SHORTCUT_ACCESSORY`, which nothing defines). INGREDIENTS.md declares this deviation. Recaulk back-fills `LSCopyDefaultApplicationURLForURL` itself. The list belongs in the recipes, with shipyard's overlay passing it to the link; until then the product keeps it.

`patches/0001` makes image_decoder's two casts to CF types `__bridge`, so clang22 accepts them under ARC. `patches/0005` declares `kTerminalFileShouldStopNotification` `extern` in `TerminalFile.h`, which defined it in every importer.

## Identity and coexistence

The app runs beside upstream iTerm2 and shares none of its writable state. Its preferences domain is its bundle id, `dev.mavergreen.iterm2.app`. `patches/0006` makes its support directory follow `CFBundleName`: `~/Library/Application Support/Mavericks iTerm2`, where shell and pasteboard history already were. Upstream's code used the executable name (`iTerm2`, shared by both apps) and the literal `iTerm`, whose `Scripts/AutoLaunch.scpt` runs at every launch. `patches/0010` gives the session servers' sockets their own prefix (`/var/tmp/Mavericks-iTerm2.socket.<pid>`). At launch the app adopts every orphaned server with its prefix, so with upstream's prefix either app would take over the other's sessions after a crash. The hotkey window and the URL handler now recognize this app by its own bundle id. What stays shared, on purpose: the password manager's keychain service (`iTerm2`, the same user's passwords). What stays upstream's: two error domains, and text that names upstream's preferences file. It has no other sockets or named connections, and it declares URL types without ever making itself their default. `tests/identity-test.sh` holds the prepared source to this. SMOKE.md is the first-launch checklist; `build/coexistence-evidence.sh` records upstream's preferences and support directories before and after, and names anything that changed.

## Dependency dispositions

`components/dependencies.tsv` names each framework the pinned release links or embeds, and what this build does with it:

- **ColorPicker** is rebuilt from the source in the pinned archive (`ColorPicker/`, LGPL 2.1) by `cmake/ITermColorPicker.cmake`: an x86_64 framework, version A, install name `@rpath/ColorPicker.framework/Versions/A/ColorPicker`, at the 10.9 floor. The prebuilt framework, ColorPickerDemo and ColorPickerTests are never inputs.
- **Growl** is dropped: it is defunct, and the prebuilt framework's source and license are unidentified. `patches/0002` delivers notifications through `NSUserNotificationCenter`, keeping every class, selector and stored name.
- **NMSSH** is dropped: its prebuilt framework carries libssh2 1.7.0 (CVE-2019-3855) and OpenSSL 1.0.2g. `patches/0003` makes every scp transfer fail visibly, with the reason.
- **Sparkle** (the old embedded engine) is dropped; see "Updates".

No Growl, NMSSH, libssh2 or Sparkle file, load command or symbol may reach the app.

## Updates

The family updater, not an embedded Sparkle, checks for and installs updates. `patches/0004` removes Sparkle's code and keeps upstream's restart handling: Sparkle's will-restart notification sets `sparkleRestarting`, so a quit for an update leaves restorable sessions' jobs running for the relaunch. The updater runs `Contents/MacOS/restart-for-update` (`product/restart-for-update.m`) after an install, as its `POST_UPDATE_HELPER`. The helper posts that notification on the distributed center, quits iTerm2 through its usual quit path, waits for it to exit, and relaunches it by bundle id. Any process in the session can post there, so the flag counts for 60 seconds only, and a declined quit clears it. Check for Updates launches the family updater with `--user`, which always shows its window. Its bundle id comes only from shipyard's product registry (`product-name.sh updater-bundle-id iterm2`), as `ITERM_UPDATER_BUNDLE_ID`; the release page comes from the registered repository, as `ITERM_RELEASES_URL`. A missing updater, or one that cannot be opened, is explained in an alert. The updater (`iterm2-updater`, built beside the app with upstream's icon and the family's public key in `updater/ed25519_key.pub`) checks daily on its own; General › "Check for updates automatically" is its `SUEnableAutomaticChecks`, kept in its defaults domain (`product/iTermFamilyUpdaterPreferences.m`).

Upstream's compiled MainMenu.nib instantiates a class named `SUUpdater` as Check for Updates' target. This build has no nib compiler, and editing the XIB would break the pairing with the compiled nib, so `product/SUUpdater.m` defines that class with only `checkForUpdates:`, which forwards to the app delegate. `product/iTermFamilyVersion.m` keeps the version ordering iTerm2's incompatible-software checks took from Sparkle.

## Package

`build/package-pkg.sh --app APP --updater-app UPDATER --version V --out DIR` makes `iterm2-V.pkg` with shipyard's stevedore seams: `dev.mavergreen.base` first, then `dev.mavergreen.iterm2`, with the 10.9.5 floor. It installs the app at `/Applications/Mavericks iTerm2.app` and the family updater with its daily-check agent; the tree `/usr/local/mavergreen/iterm2` holds only the manifest, since iTerm2 has no command-line tools. It refuses an app that is not `dev.mavergreen.iterm2.app`, is another version, or lacks `Contents/MacOS/restart-for-update`. `tests/package-test.sh` packages stand-ins on any host, and the native build's app when there is one, and runs shipyard's artifact conformance on each.

`build/app-inventory.sh APP` prints what a native and a cross build of one commit must agree on: every file's path and, for each slice of each Mach-O (thinned out, since a reader given a universal file reads the host's own slice), digests of its load commands (kinds, dylibs, rpaths, minimum OS), undefined symbols and defined external symbols.

## Acceptance on 10.9

`build/check-release-on-10.9.sh [--drivers TAR] [--repo-tests] VERSION` is what CI's 10.9 guest runs on each release's own pkg, and what a person can run on a 10.9 Mac. It checks the pkg against `SHA256SUMS` and installs nothing unless that and the checks before it pass. Then it installs the pkg, checks the manifest, the app, the updater and its agent, runs the post-update helper with no instance running, installs the pkg again over itself, and runs the packed driver tests (`build/pack-drivers.sh`, which packs `ColorPicker.framework` beside them; a driver's `@executable_path/.` rpath finds it there, and `tests/pack-drivers-test.sh` holds the pack to that), the image decoder's against the installed `image_decoder`. Last it uninstalls and checks that nothing of it is left and that upstream iTerm2's state is unchanged. The guest has no GUI session, so the app's windows are checked by hand with SMOKE.md. Tests that need clang22 or `shipyard-cmake` skip (77) where those are not installed, as in the guest.

## Resources and the bundle

The 29 nibs and the compiled Core Data model come from the release ZIP (`resources/compiled.tsv`, each at its measured size and SHA-256), staged by shipyard's `mavericks_extract_resource_members`, which also checks the ZIP's own version. Every other resource is copied from the pinned source as `resources/app-resources.tsv` lists. `resources/source-contract.json` records what is verified about the source-to-nib pairing and what is not.

`build/assemble-bundle.sh` builds `iTerm2.app` from those inputs, the rebuilt executables and ColorPicker: image_decoder in `Contents/Resources` (where iTerm2 finds it with `pathForResource`), mode 0755, beside its sandbox profile; `iTerm2.icns` made by `iconutil` from the asset catalog's AppIcon (a catalog with anything more is refused, since there is no `actool`); the PNG pairs as they are, which `NSImage` resolves by name; and upstream's Info.plist with this product's identity (`dev.mavergreen.iterm2.app`, Mavericks iTerm2), its `<upstream>-mavericks.N` version and that version's comparison key, the 10.9 floor and no Sparkle keys. `build/check-bundle.sh` refuses any bundle that differs from these inputs, including any extra executable, any run path outside the bundle (the executable links with its install run path, never the build tree's) and any binary it cannot read.

## Build evidence

`build/record-build.sh BUILD_DIR EVIDENCE_DIR` builds the app, keeps the whole log and the real exit status, and writes `findings.json`: PASS only for a complete build whose output exists, passes shipyard's compat guard and leaves the checkout unchanged; BLOCKED otherwise. It records the host, mode, compiler and its version, shipyard's version, the declared inputs and the output's inventory. A leg that was not run is recorded with `--absent` as ABSENT, with its reason. Runtime behavior is never measured here: it stays UNMEASURED until a separately authorized acceptance run. After a native build passes so far, it builds the `drivers` target and runs the driver tests (CTest label `driver`), recording `drivers` PASS or FAIL; a failing driver makes the build BLOCKED. A driver is a small Objective-C program in `tests/drivers/` that links the built `iTerm2Shared` (and the app's own sources, all but `main.m`) and checks behavior a grep cannot, such as what the tmux gateway writes. A cross build records the drivers UNMEASURED, with the reason: its x86_64 10.9 drivers do not run on its host. A build that did not pass records them UNMEASURED, since they never ran. A build that defines none records NONE.

A normal build stops at the first failed target and skips everything that depends on it. `build/sweep.sh BUILD_DIR OUT_DIR` measures every unit anyway: it syntax-checks each entry of `compile_commands.json` (the presets export it) and writes every error to `errors.tsv`. It is a diagnostic, never the verdict. While declaration fixes are iterated, `-DITERM_UNRELEASED_RECIPES=<path>` builds against a Recaulk working tree's recipes; the build records it, and `record-build.sh` reports such a build BLOCKED, naming the recipes, however it builds. The setting stays in the build directory's cache, so a reconfigure that leaves it out still builds against them; `-UITERM_UNRELEASED_RECIPES` returns to the pinned recipes.

## Security advisories

`SECURITY.md` and `security/advisories.tsv` record every published iTerm2 advisory against the pinned source: fixed by a patch, guarded by a check 3.0.15 already has, absent because 3.0.15 lacks the feature, or pending. `tests/advisories-test.sh` prepares the source and fails, naming the advisory, when an absent feature appears, a guard disappears or a fix's patch is no longer applied, so moving to a newer upstream cannot bring an advisory back unnoticed.

## Building a commit on another host

Take committed state with `git archive`, never a shared work tree, and give each extract its own directory name (`mavergreen-iterm2-<commit>`). The presets name the build directory after the source directory under `$TMPDIR/mm-build` and do not take a caller's build root, so two extracts with the same name would share one; `-B <dir>` on the configure also separates them.
