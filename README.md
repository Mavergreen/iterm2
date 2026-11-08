# Mavericks iTerm2

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut its first release.

iTerm2 3.0.15 for Mac OS X 10.9 (Mavericks), with the security fixes upstream made after it. 3.0.15 is the last iTerm2 release that supports 10.9. This is an unofficial community build, not affiliated with iTerm2 or its author.

## Install

Download `iterm2-<version>.pkg` from the [releases](https://github.com/Mavergreen/iterm2/releases) and open it. It installs `/Applications/Mavericks iTerm2.app` and its updater, and needs Mac OS X 10.9.5 or later.

It runs beside upstream iTerm2 without sharing its settings, support files or sessions. Its preferences are `dev.mavergreen.iterm2.app`, and its support files are in `~/Library/Application Support/Mavericks iTerm2`. The password manager uses the same keychain entries as upstream, so the first use asks for access to them.

## Updates

The updater checks daily, and iTerm2 › Check for Updates checks at once. General › "Check for updates automatically" turns the daily check off.

After an update installs, iTerm2 quits and relaunches. Sessions that can be restored come back with their jobs still running, as with upstream's own updates. If you need every session kept exactly as it is, quit iTerm2 yourself before installing.

## What differs from upstream 3.0.15

- [SECURITY.md](SECURITY.md) lists every published iTerm2 advisory and where each stands. The ones that apply to 3.0.15 are fixed.
- Secure copy (scp) through shell integration is unavailable: its library had known vulnerabilities.
- Notifications use Notification Center; Growl is not supported.
- The family updater replaces upstream's built-in Sparkle.
- Only the app's command-line behavior is tested on 10.9 in CI. Its windows are checked by hand on each release, following [SMOKE.md](SMOKE.md).

[PORT.md](PORT.md) lists every change to upstream's source and why.

## Build

Install the family's shipyard, clang22 (`clang22-cross` on a modern Mac) and Recaulk at the releases the `components/` pins name. Then:

```sh
sh build/prepare-inputs.sh "$TMPDIR/mm-build/mavergreen-iterm2-inputs"
shipyard-cmake --preset native        # --preset cross on a modern Mac
shipyard-cmake --build --preset native
```

`build/prepare-inputs.sh` fetches and verifies the pinned source and resources, applies `patches/`, and refuses any tool not installed at its pin. [BUILD.md](BUILD.md) describes the build, and [INGREDIENTS.md](INGREDIENTS.md) its inputs.
