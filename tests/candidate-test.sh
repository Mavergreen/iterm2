#!/bin/sh
# platform: host-agnostic
# spec: candidates/README.md -- a tracked candidate upstream: pins of the shipping pins' form naming one
#       upstream version, patches that ship (never a research-only one), and its census settings.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
val() { sed -n "s/^$2=//p" "$1"; }
n=0
for c in "$REPO_ROOT"/candidates/*/; do
  [ -d "$c" ] || continue
  n=$((n + 1)); name=$(basename "$c")
  # spec: build/prepare-inputs.sh -- the same patterns the shipping pins must match
  up=$(cat "$c/UPSTREAM_VERSION" 2>/dev/null || :)
  printf '%s\n' "$up" | grep -Eqx '[0-9]+(\.[0-9]+)*' || fail "candidate_pins_well_formed: $name UPSTREAM_VERSION is '$up'"
  [ "$up" = "$name" ] || fail "candidate_pins_well_formed: candidates/$name names upstream $up"
  s=$c/components/iterm2/version; r=$c/components/iterm2-resources/version
  [ "$(val "$s" REF)" = "v$up" ] || fail "candidate_pins_well_formed: $name REF is '$(val "$s" REF)'"
  val "$s" DIGEST | grep -Eqx '[0-9a-f]{40}' || fail "candidate_pins_well_formed: $name DIGEST"
  val "$s" SHA256 | grep -Eqx '[0-9a-f]{64}' || fail "candidate_pins_well_formed: $name source SHA256"
  val "$r" SHA256 | grep -Eqx '[0-9a-f]{64}' || fail "candidate_pins_well_formed: $name resources SHA256"
  [ "$(val "$r" VERSION)" = "$up" ] || fail "candidate_pins_well_formed: $name resources VERSION"
  [ -s "$c/census-settings" ] || fail "candidate_has_census_settings: $name"
  [ -d "$c/patches" ] || fail "candidate_has_patches_dir: $name"
  for p in "$c"/patches/*; do
    [ -e "$p" ] || continue
    case $(basename "$p") in [0-9][0-9][0-9][0-9]-*.patch) ;; *) fail "candidate_patch_named: $name/$(basename "$p")" ;; esac
    case $(basename "$p") in *census*) fail "no_research_patch_in_candidate: $name/$(basename "$p")" ;; esac
    ! grep -qi 'RESEARCH ONLY' "$p" || fail "no_research_patch_in_candidate: $name/$(basename "$p") says RESEARCH ONLY"
  done
done
[ "$n" -gt 0 ] || fail "candidates: none found"
[ "$fails" -eq 0 ] || { echo "candidate-test: $fails failure(s)" >&2; exit 1; }
echo "candidate-test: OK"
