# Carried changes

| Carried change | What it does | Upstream destination | Retire when |
|---|---|---|---|
| `patches/0001-image-decoder-arc-bridges.patch` | Two `__bridge` casts in `image_decoder.m`, which builds with ARC, so clang22 accepts the conversions to CF types | gnachman/iTerm2 (`image_decoder/image_decoder.m`) | upstream's pinned release has the casts |
| `patches/0002-notifications-user-notification-center.patch` | `iTermGrowlDelegate` delivers `NSUserNotification`s instead of calling Growl; class, selectors, the `BM Growl` key and `GrowlTrigger` unchanged | none: upstream later dropped Growl itself | the product moves to an upstream release without Growl |
| `patches/0003-scp-transfers-unavailable.patch` | `SCPFile` registers each transfer, then fails it with the reason; no NMSSH or libssh2 | none (a product security decision) | the family has a maintained libssh2 and OpenSSL for 10.9 and NMSSH is rebuilt against them |
| `patches/0004-family-updater.patch` | removes every Sparkle use, including the `sparkleRestarting` property and the quit path that trusted a Sparkle restart; Check for Updates launches the family updater (`ITERM_UPDATER_BUNDLE_ID`, from shipyard's registry) with `--user`, and says whether it is missing or failed to open, naming the release page; hides the two Sparkle checkboxes | none (family updater integration) | never, while the product uses the family updater |
| `patches/0005-terminal-file-extern.patch` | `TerminalFile.h` declares `kTerminalFileShouldStopNotification` `extern`; the header defined it in every file that imported it, which the project's `GCC_NO_COMMON_BLOCKS = YES` makes a duplicate symbol | gnachman/iTerm2 (`sources/TerminalFile.h`) | upstream's pinned release declares it `extern` |
| `patches/0006-coexist-with-upstream.patch` | the support directory (and the legacy one holding `Scripts/AutoLaunch.scpt`) follows `CFBundleName`, so this app never reads or writes upstream's `~/Library/Application Support/iTerm` or `iTerm2`; the hotkey window and URL-handler checks compare against this app's own bundle id | none (a product identity decision) | never, while the product runs beside upstream iTerm2 |
| `product/iTermFamilyVersion.m` | the version ordering iTerm2's four incompatible-software checks took from Sparkle: dotted numbers numerically, a suffixed version a prerelease of the plain one | none | the product compiles against an upstream without those checks |
| `product/SUUpdater.m` | a class named `SUUpdater` with only `checkForUpdates:`, so upstream's compiled MainMenu.nib binds its menu item; no Sparkle code | none | the product compiles its own nibs |

## Decisions recorded with the maintainer (2026-11-07)

- Growl is dropped: notifications go through `NSUserNotificationCenter` (10.8+).
- ColorPicker is rebuilt from the source in the pinned archive (LGPL 2.1), never copied prebuilt.
- NMSSH is dropped: its prebuilt framework carries libssh2 1.7.0 (CVE-2019-3855) and OpenSSL 1.0.2g. scp transfers report that they are unavailable, until the family has a maintained libssh2 and OpenSSL for 10.9.
- The embedded Sparkle is dropped: Check for Updates launches the family updater.

## Bundle assembly

- The 29 nibs and the compiled Core Data model come from upstream's 3.0.15 release ZIP (`resources/compiled.tsv`, measured hashes), extracted by shipyard's `mavericks_extract_resource_members`; this build has no nib or model compiler. `resources/source-contract.json` records what is verified about that pairing and what is not.
- Every other resource is copied from the pinned source as listed in `resources/app-resources.tsv`. Upstream's Xcode combined `foo.png` and `foo@2x.png` into HiDPI TIFFs (`COMBINE_HIDPI_IMAGES`); this build ships the PNG pairs, which `NSImage` resolves by name the same way.
- `iTerm2.icns` is made by `iconutil` from `Media.xcassets/AppIcon.appiconset`; a catalog with anything more is refused.
- Info.plist is upstream's with the identity from the design spec (`dev.mavergreen.iterm2.app`, Mavericks iTerm2), the `-mavericks.N` version and its comparison key, the 10.9 floor, and no Sparkle keys. `build/check-bundle.sh` refuses any bundle that differs from these inputs.
- Dropped from upstream's bundle: `dsa_pub.pem` (Sparkle), `Growl Registration Ticket.growlRegDict`, and the Growl, NMSSH and Sparkle frameworks.
