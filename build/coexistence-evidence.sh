#!/bin/sh
# platform: macOS-only -- reads sizes and times with stat -f and preferences with defaults export.
#   usage: coexistence-evidence.sh before|after EVIDENCE_DIR
#          before records upstream iTerm2's preferences (com.googlecode.iterm2, as a SHA-256 of what
#          defaults read prints) and every file under ~/Library/Application Support/iTerm and iTerm2 (size,
#          mtime, path) in EVIDENCE_DIR/before.txt; after records the same in after.txt and exits 1,
#          naming each difference, when they differ. It never writes either location.
# spec: BUILD.md "Identity and coexistence" -- this app runs beside upstream iTerm2 and must change none of
#       its state. Upstream running at the same time may change its own state: a difference is evidence
#       to read, naming the file, not a verdict on its own.
set -eu
[ "$#" -eq 2 ] && { [ "$1" = before ] || [ "$1" = after ]; } || { echo 'usage: coexistence-evidence.sh before|after EVIDENCE_DIR' >&2; exit 2; }
PHASE=$1; E=$2
DEFAULTS=${COEXIST_DEFAULTS:-defaults}
AS="$HOME/Library/Application Support"
record() {
  # platform: 10.9's defaults has no export verb; read prints the whole domain
  prefs=$("$DEFAULTS" read com.googlecode.iterm2 2>/dev/null) || prefs=""
  [ -n "$prefs" ] || { echo "coexistence-evidence: cannot read com.googlecode.iterm2" >&2; return 1; }
  printf 'prefs com.googlecode.iterm2 %s\n' "$(printf '%s\n' "$prefs" | shasum -a 256 | cut -d' ' -f1)"
  for d in iTerm iTerm2; do
    if [ -d "$AS/$d" ]; then
      (cd "$AS" && find "$d" -print | LC_ALL=C sort | while IFS= read -r f; do
         printf 'file %s\n' "$(stat -f '%z %m' "$f") $f"
       done)
    else
      printf 'absent %s\n' "$d"
    fi
  done
}
mkdir -p "$E"
if [ "$PHASE" = before ]; then
  record > "$E/before.txt" || { rm -f "$E/before.txt"; exit 1; }
  echo "coexistence-evidence: recorded $E/before.txt"
  exit 0
fi
[ -f "$E/before.txt" ] || { echo "coexistence-evidence: no $E/before.txt; run before first" >&2; exit 2; }
record > "$E/after.txt" || exit 1
if cmp -s "$E/before.txt" "$E/after.txt"; then
  echo "coexistence-evidence: upstream iTerm2's preferences and support directories are unchanged"
  exit 0
fi
echo "coexistence-evidence: upstream iTerm2's state changed:" >&2
diff "$E/before.txt" "$E/after.txt" | sed -n 's/^\([<>]\) /  \1 /p' >&2
exit 1
