# Security

Mavericks iTerm2 is iTerm2 3.0.15, from 2017. Upstream has fixed security bugs since then, and this product carries the fixes that apply to the code it ships. This file is the ledger of every published iTerm2 advisory and where each stands against the pinned source. `security/advisories.tsv` is its machine-readable form, and `tests/advisories-test.sh` checks it against the prepared source on every test run.

## Statuses

- **fixed**: a patch in `patches/` backports upstream's fix. The test fails if that patch is no longer applied.
- **guarded**: 3.0.15 already has the check whose absence was the bug. The test fails if that check (the row's marker) disappears from the source.
- **absent**: 3.0.15 does not have the feature the advisory is about. The test fails, naming the advisory, if the feature's marker appears in the source. That is how a newer upstream re-arms the advisory: backport the fix, or re-rule the row.
- **pending**: it applies, or might, and is not resolved yet. The release gate says when it must be.

Each marker's `security/fixtures/<id>.txt` is an excerpt of what the feature looks like when present, so a marker that could never match fails the test too.

## The advisories

| Advisory | Fixed upstream in | What | Status |
|---|---|---|---|
| CVE-2019-9535 | 3.3.6 | tmux integration sends names the server controls as tmux commands, so terminal output can run commands | fixed: `patches/0008` targets sessions by number and hex-encodes stored options, as upstream does |
| CVE-2023-46300 | 3.4.20 | tmux integration runs a command left typed before integration starts; upstream sends Control-C first | fixed: `patches/0007` sends Control-C first, as upstream does |
| CVE-2015-9231 | 3.1.1 | text under the pointer is looked up over DNS (`AsyncHostLookupController`), leaking it | pending: fixed before daily use |
| CVE-2022-45872 | 3.4.18 | the DECRQSS reply echoes its argument | absent: 3.0.15 has no DECRQSS reply |
| CVE-2023-46301 | 3.4.20 | the upload escape sequence's reply contains a newline | absent: 3.0.15 has no upload sequence |
| CVE-2024-38395 | 3.5.2 | title reports answered regardless of their setting | guarded: 3.0.15 answers only when the profile allows title reporting, which is off by default |
| CVE-2024-38396 | 3.5.2 | title reporting combined with tmux integration | guarded: as CVE-2024-38395 |
| CVE-2025-22275 | 3.5.11 | SSH integration logs session input and output on the remote host | absent: 3.0.15 has no SSH integration |
| CVE-2019-19022 | after 3.3.6 | search history is saved in the preferences file, which people publish with their dotfiles | absent: 3.0.15 keeps no search history (only the case and regex settings; the search string goes to the system Find pasteboard) |
| CVE-2026-41253 | after 3.6.9 | not yet traced to 3.0.15's code | pending: resolved before the first release |
| ITERM2-URL-SCHEME | — | `ssh:`, `telnet:` and `x-man-page:` links become a session's command (only through a profile configured as their handler) | pending: resolved before the first release |

## Reporting a problem

This product has no public repository yet. Until it does, report a security problem to the maintainer directly, not in a public place. Problems in iTerm2 itself belong upstream at https://iterm2.com.
