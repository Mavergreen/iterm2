# Carried changes

| Carried change | What it does | Upstream destination | Retire when |
|---|---|---|---|
| `patches/0001-image-decoder-arc-bridges.patch` | Two `__bridge` casts in `image_decoder.m`, which builds with ARC, so clang22 accepts the conversions to CF types | gnachman/iTerm2 (`image_decoder/image_decoder.m`) | upstream's pinned release has the casts |
| `patches/0002-notifications-user-notification-center.patch` | `iTermGrowlDelegate` delivers `NSUserNotification`s instead of calling Growl; class, selectors, the `BM Growl` key and `GrowlTrigger` unchanged | none: upstream later dropped Growl itself | the product moves to an upstream release without Growl |
| `patches/0003-scp-transfers-unavailable.patch` | `SCPFile` registers each transfer, then fails it with the reason; no NMSSH or libssh2 | none (a product security decision) | the family has a maintained libssh2 and OpenSSL for 10.9 and NMSSH is rebuilt against them |
| `patches/0004-family-updater.patch` | removes every Sparkle use, including the `sparkleRestarting` property and the quit path that trusted a Sparkle restart; Check for Updates launches the family updater (`ITERM_UPDATER_BUNDLE_ID`, from shipyard's registry) with `--user`, and says whether it is missing or failed to open, naming the release page; hides the two Sparkle checkboxes | none (family updater integration) | never, while the product uses the family updater |
| `product/iTermFamilyVersion.m` | the version ordering iTerm2's four incompatible-software checks took from Sparkle: dotted numbers numerically, a suffixed version a prerelease of the plain one | none | the product compiles against an upstream without those checks |
| `product/SUUpdater.m` | a class named `SUUpdater` with only `checkForUpdates:`, so upstream's compiled MainMenu.nib binds its menu item; no Sparkle code | none | the product compiles its own nibs |

## Decisions recorded with the maintainer (2026-11-07)

- Growl is dropped: notifications go through `NSUserNotificationCenter` (10.8+).
- ColorPicker is rebuilt from the source in the pinned archive (LGPL 2.1), never copied prebuilt.
- NMSSH is dropped: its prebuilt framework carries libssh2 1.7.0 (CVE-2019-3855) and OpenSSL 1.0.2g. scp transfers report that they are unavailable, until the family has a maintained libssh2 and OpenSSL for 10.9.
- The embedded Sparkle is dropped: Check for Updates launches the family updater.

