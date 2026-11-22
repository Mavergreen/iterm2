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
  # spec: candidates/README.md "3.2.9" -- a define the table sets is one its patches honour, the census
  #       compiles each target with its row's defines, and a driver the table names has its source
  t=$c/targets.cmake
  if [ -f "$t" ]; then
    for d in $(sed -n 's/.*DEFINES \([A-Za-z_][A-Za-z0-9_=]*\).*/\1/p' "$t" | sort -u); do
      cat "$c"/patches/*.patch 2>/dev/null | grep -q -- "${d%%=*}" \
        || fail "table_define_has_patch: $name sets $d, which none of its patches mentions"
    done
    for row in $(sed -n 's/^set(ITERM_ROW_\([A-Za-z0-9_]*\)$/\1/p' "$t"); do
      want=$(awk -v r="set(ITERM_ROW_$row" '$0==r{f=1;next} f&&/^set\(/{f=0} f' "$t" | sed -n 's/.*DEFINES \([^ )]*\).*/\1/p')
      got=$(awk -v r="TARGET=$row" '$0==r{f=1;next} f&&/^$/{f=0} f' "$c/census-settings" | sed -n 's/^DEFINES=//p')
      [ "$want" = "$got" ] || fail "census_defines_match_table: $name $row defines '$got' in census-settings, '$want' in targets.cmake"
    done
    for drv in $(sed -n 's/^set(ITERM_TABLE_DRIVERS \(.*\))$/\1/p' "$t"); do
      [ -f "$REPO_ROOT/tests/drivers/$drv-driver.m" ] || fail "table_driver_has_source: $name names driver $drv"
    done
  fi
done
[ "$n" -gt 0 ] || fail "candidates: none found"
[ "$fails" -eq 0 ] || { echo "candidate-test: $fails failure(s)" >&2; exit 1; }
echo "candidate-test: OK"
