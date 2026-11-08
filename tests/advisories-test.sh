#!/bin/sh
# platform: macOS-only -- prepares the pinned source with shipyard's fetch and patch scripts.
# spec: SECURITY.md -- every published iTerm2 advisory is a row of security/advisories.tsv, and the row's
#       status is checked against the prepared source: an absent feature's marker must not appear, a
#       guarding check's marker must stay, a fix's patch must be applied. An upstream bump that brings
#       a feature in, or drops a guard or a fix, fails here and names the advisory.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-advisories-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
. "$REPO_ROOT/build/msc.sh"
L="$REPO_ROOT/security/advisories.tsv"
TAB=$(printf '\t')

[ -f "$L" ] || { echo "advisories-test: no security/advisories.tsv" >&2; exit 1; }
[ "$(head -1 "$L")" = "$(printf 'id\tfixed_in\tfeature\tstatus\tmarker\tpatch')" ] || fail "advisories.tsv header"
v() { sed -n "s/^$1=//p" "$REPO_ROOT/components/iterm2/version"; }
sh "$SHIPYARD_SCRIPTS/fetch_pinned_source.sh" "$(v REPO)" "$(v DIGEST)" "$(v SHA256)" "$T/src" 2>/dev/null \
  || { echo "advisories-test: the pinned source did not fetch" >&2; exit 1; }
sh "$SHIPYARD_SCRIPTS/apply_patches.sh" "$T/src" "$REPO_ROOT/patches" >/dev/null 2>&1 \
  || { echo "advisories-test: patches/ does not apply" >&2; exit 1; }

check() { # LEDGER [FIXTURES_DIR [PATCHES_DIR]]
  F=${2:-$REPO_ROOT/security/fixtures}
  P=${3:-$REPO_ROOT/patches}
  tail -n +2 "$1" | while IFS="$TAB" read -r id fixed feature status marker patch; do
    [ -n "$id" ] && [ -n "$fixed" ] && [ -n "$feature" ] || { echo "$id: a row needs id, fixed_in and feature"; continue; }
    case "$status" in
      absent|guarded)
        [ "$patch" = - ] && [ "$marker" != - ] || { echo "$id: $status needs a marker and no patch"; continue; }
        hits=$(grep -rlE --include='*.m' --include='*.h' --include='*.swift' --include='*.c' -- "$marker" \
                 "$T/src/sources" "$T/src/ThirdParty" 2>/dev/null | sed "s|$T/src/||" | tr '\n' ' ')
        if [ "$status" = absent ] && [ -n "$hits" ]; then echo "$id: its feature is now in the source ($hits): fix it or re-rule it"; fi
        if [ "$status" = guarded ] && [ -z "$hits" ]; then echo "$id: the guarding check is gone from the source: fix it or re-rule it"; fi
        if [ ! -f "$F/$id.txt" ] || ! grep -qE -- "$marker" "$F/$id.txt"; then
          echo "$id: its marker does not match its fixture security/fixtures/$id.txt"
        elif [ "$status" = guarded ] && [ -n "$hits" ]; then
          # spec: SECURITY.md "Statuses" -- a guarded fixture quotes every guarded site, so losing one
          #       site while another remains still fails
          want=$(grep -cE -- "$marker" "$F/$id.txt")
          have=$(grep -rhE --include='*.m' --include='*.h' --include='*.swift' --include='*.c' -- "$marker" \
                   "$T/src/sources" "$T/src/ThirdParty" 2>/dev/null | wc -l | tr -d ' ')
          [ "$have" -ge "$want" ] || echo "$id: the guard is at $have site(s); its fixture quotes $want: fix it or re-rule it"
        fi ;;
      fixed)
        [ "$marker" = - ] && [ -f "$P/$patch" ] || { echo "$id: fixed needs patches/$patch and no marker"; continue; }
        grep -q "$(shasum -a 256 "$P/$patch" | cut -d' ' -f1)" "$T/src/.mavergreen-patches" \
          || echo "$id: patches/$patch is not applied" ;;
      pending)
        [ "$marker" = - ] && [ "$patch" = - ] || echo "$id: pending takes no marker or patch" ;;
      *) echo "$id: unknown status '$status'" ;;
    esac
    grep -qF -- "$id" "$REPO_ROOT/SECURITY.md" || echo "$id: SECURITY.md does not name it"
  done
}
check "$L" > "$T/problems"
[ ! -s "$T/problems" ] || { sed 's/^/  /' "$T/problems" >&2; fail "the ledger disagrees with the prepared source"; }
[ "$(tail -n +2 "$L" | awk -F'\t' '$4 == "absent"' | wc -l | tr -d ' ')" -ge 1 ] || fail "no absent row to exercise"

cp "$L" "$T/ledger.tsv"
printf 'TEST-REARM\t9.9\tthe tmux gateway\tabsent\tTmuxGateway\t-\n' >> "$T/ledger.tsv"
check "$T/ledger.tsv" | grep -q '^TEST-REARM: its feature is now in the source' || fail "an absent feature that is present does not fail"
printf 'id\tfixed_in\tfeature\tstatus\tmarker\tpatch\nTEST-GUARD\t9.9\tnothing\tguarded\tNoSuchGuardAnywhere\t-\n' > "$T/guard.tsv"
check "$T/guard.tsv" | grep -q '^TEST-GUARD: the guarding check is gone' || fail "a missing guard does not fail"
mkdir -p "$T/fx"
printf 'NoSuchGuardAnywhere\n' > "$T/src/sources/Decoy.xib"
cp "$T/src/sources/Decoy.xib" "$T/fx/TEST-GUARD.txt"
check "$T/guard.tsv" "$T/fx" | grep -q '^TEST-GUARD: the guarding check is gone' \
  || fail "a guard found only outside source files counts as present"
rm "$T/src/sources/Decoy.xib"
printf 'id\tfixed_in\tfeature\tstatus\tmarker\tpatch\nTEST-SITES\t9.9\ttwo sites\tguarded\t- \\(NSString \\*\\)terminalWindowTitle \\{\t-\n' \
  > "$T/sites.tsv"
printf -- '- (NSString *)terminalWindowTitle {\n- (NSString *)terminalWindowTitle {\n' > "$T/fx/TEST-SITES.txt"
check "$T/sites.tsv" "$T/fx" | grep -q '^TEST-SITES: the guard is at 1 site(s); its fixture quotes 2' || fail "a guard at fewer sites than its fixture quotes does not fail"
printf 'id\tfixed_in\tfeature\tstatus\tmarker\tpatch\nTEST-FIXED\t9.9\tapplied\tfixed\t-\t0001-image-decoder-arc-bridges.patch\nTEST-UNAPPLIED\t9.9\tnot applied\tfixed\t-\tunapplied.patch\n' > "$T/fixed.tsv"
mkdir -p "$T/pp"; cp "$REPO_ROOT"/patches/*.patch "$T/pp/"; printf 'a patch no build applied\n' > "$T/pp/unapplied.patch"
check "$T/fixed.tsv" "$T/fx" "$T/pp" > "$T/fixed.out"
! grep -qE '^TEST-FIXED: (fixed needs|patches/)' "$T/fixed.out" || fail "a fixed row whose patch is applied is reported: $(cat "$T/fixed.out")"
grep -q '^TEST-UNAPPLIED: patches/unapplied.patch is not applied' "$T/fixed.out" || fail "a fixed row whose patch is not applied passes"

[ "$fails" -eq 0 ] || { echo "advisories-test: $fails failure(s)" >&2; exit 1; }
echo "advisories-test: OK"
