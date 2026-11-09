# Mavericks iTerm2

iTerm2 for Mac OS X 10.9 Mavericks.

This is upstream's code from back when it was last known to build on 10.9, plus upstream's security fixes backported to 10.9.

## What differs from upstream

- [SECURITY.md](SECURITY.md) lists every published iTerm2 advisory and where each stands.
- `scp` through shell integration is unavailable: its library had known vulnerabilities.
- Notifications use Notification Center; Growl is not supported.
- The updater is Mavergreen's, not upstream's.
