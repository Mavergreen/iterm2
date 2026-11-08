#!/bin/sh
# platform: host-agnostic
#   usage: upstream-release-notes-url.sh UPSTREAM_VERSION
#          Prints upstream iTerm2's changelog for that release, as iterm2.com publishes it beside the
#          download (3.0.15 -> iTerm2-3_0_15.changelog); shipyard's upstream-notes.sh links it.
set -eu
v=${1:?usage: upstream-release-notes-url.sh <upstream-version>}
printf 'https://iterm2.com/downloads/stable/iTerm2-%s.changelog\n' "$(printf '%s' "$v" | tr . _)"
