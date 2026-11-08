# First-launch smoke checklist

These are the checks a person makes when Mavericks iTerm2 first runs on a 10.9 Mac beside upstream iTerm2. Phase 3's acceptance job automates them on each release's own package. The app runs from the build directory and is never installed over anything.

## Before launching

1. Quit nothing. Upstream iTerm2 may stay running: this app never touches it.
2. Record upstream's state: `sh build/coexistence-evidence.sh before "$EVIDENCE"`.
3. Launch a new instance from the build directory: `open -n "$BUILD/iTerm2.app"`. Always use `-n`, so Launch Services never brings forward upstream's running app instead.

## Checks

Note each result, pass or fail, with anything surprising.

1. **Window and shell.** A window opens with a shell prompt, and `echo $TERM_PROGRAM` prints `iTerm.app`.
2. **Preferences.** iTerm2 › Preferences opens with every tab drawn, which shows the compiled nibs load.
3. **Own preferences domain.** In the new window, `defaults read dev.mavergreen.iterm2.app | head` prints this app's settings.
4. **Notes.** Toolbelt › Show Toolbelt, then Toolbelt › Notes. Type a line. It is saved to `~/Library/Application Support/Mavericks iTerm2/notes.rtfd`.
5. **Inline image.** `printf '\033]1337;File=inline=1:%s\a\n' "$(base64 < "$BUILD/iTerm2.app/Contents/Resources/BigArrow.png")"` draws an arrow. That shows image_decoder runs.
6. **Notification.** Preferences › Profiles › Terminal › "Send Growl/Notification Center alerts" is on in the default profile. Run `sleep 10; printf '\a'`, then hide the app (⌘H) or minimize its window. A "Bell" notification appears, and clicking it brings the session back. Switching apps isn't enough: like upstream 3.0.15, the app notifies only when the window is out of sight.
7. **Check for Updates.** iTerm2 › Check for Updates explains that the family updater is not installed and names the release page.
8. **scp.** With shell integration absent, an scp transfer, if attempted, reports that scp is unavailable in this build.
9. **tmux integration.** Run `/opt/pkg/bin/tmux -CC`. A tmux window opens as a native iTerm2 window. Then `/opt/pkg/bin/tmux -CC attach` from a second window, detach, and reattach. iTerm2 3.0.15 predates tmux 3.6: if integration doesn't work with it, note that and test with a tmux of 3.0.15's era, because the limitation predates this build.
10. **Hover.** Hold Command over a URL. It underlines as a link at once, with no DNS lookup (CVE-2015-9231).

## After quitting

1. Quit Mavericks iTerm2 (iTerm2 › Quit). Leave upstream alone.
2. `sh build/coexistence-evidence.sh after "$EVIDENCE"`. Expected: unchanged. If upstream was running and saved its own state meanwhile, the script names those files. Read them before calling it a failure.

## Don'ts

- Don't make Mavericks iTerm2 the default terminal or the default handler for `ssh:`, `telnet:` or `x-man-page:` links (Preferences › Profiles › General › URL Schemes).
- The password manager shares upstream's keychain service (`iTerm2`). The first use asks for keychain access: allow it once, or deny it to keep the two apart.
