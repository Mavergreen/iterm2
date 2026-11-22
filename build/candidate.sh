#!/bin/sh
# platform: macOS-only -- runs prepare-inputs.sh, which reads installed product manifests with plutil.
#   usage: candidate.sh VERSION OUTPUT_ROOT
#          Prepares the tracked candidate upstream candidates/VERSION: its pins and its patches, always
#          together, through prepare-inputs.sh. The shipping pins and patches are never read for them.
# spec: candidates/README.md
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
die() { echo "candidate: $*" >&2; exit 1; }
[ "$#" -eq 2 ] || { echo 'usage: candidate.sh VERSION OUTPUT_ROOT' >&2; exit 2; }
printf '%s\n' "$1" | grep -Eqx '[0-9]+(\.[0-9]+)*' || die "a candidate name is an upstream version: $1"
[ -d "$REPO_ROOT/candidates/$1" ] || die "no candidates/$1"
[ -d "$REPO_ROOT/candidates/$1/patches" ] || die "candidates/$1 has no patches directory"
ITERM_PINS_DIR=$REPO_ROOT/candidates/$1 ITERM_PATCHES_DIR=$REPO_ROOT/candidates/$1/patches \
  exec sh "$REPO_ROOT/build/prepare-inputs.sh" "$2"
