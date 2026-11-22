#!/bin/sh
# platform: host-agnostic
#   usage: census-classify.sh BUILD_LOG BUILD_DIR OUT_DIR
#          Reads a census's Ninja log (-k 0), BUILD_DIR/compile_commands.json (one entry per compile: its
#          source and its object) and BUILD_DIR/census-targets.tsv ("<prefix>\t<target>"), and writes:
#            census.tsv   target file status(ok|error) first_error_kind first_error_symbol
#            summary.tsv  target compiled ok error
#            symbols.tsv  kind symbol files   (sorted by files, most first)
#          Every row is one compile, named by its object, so a source in two targets is judged once per
#          target. A compile is ok only if its object exists, and error only if Ninja's FAILED: line names
#          its object; a compile with neither was never compiled, and the census fails rather than count it.
#          A compile's diagnostics are those after its own Ninja line ("[n/m] Building ... <object>" or
#          "FAILED: <object>"); its first error decides its kind. Kinds: undeclared-identifier, unknown-type,
#          missing-header, no-method, unavailable, other; no-method-warning is a missing selector that only
#          warned (MRC), still a runtime gap. symbols.tsv counts distinct compiles per symbol.
# spec: BUILD.md "Census"
set -eu
[ "$#" -eq 3 ] || { echo 'usage: census-classify.sh BUILD_LOG BUILD_DIR OUT_DIR' >&2; exit 2; }
die() { echo "census-classify: $*" >&2; exit 1; }
[ -f "$1" ] || die "no log $1"
[ -s "$2/compile_commands.json" ] || die "no compile_commands.json in $2"
[ -s "$2/census-targets.tsv" ] || die "no census-targets.tsv in $2"
rm -f "$3/census.tsv" "$3/summary.tsv" "$3/symbols.tsv" "$3/symbols.body" "$3/never-compiled"
TAB=$(printf '\t')
# platform: compile_commands.json as CMake writes it, one "key": "value" per line; \" and \\ unescaped
LC_ALL=C awk '
function val(s) { sub(/^[ \t]*"[a-z]+": "/, "", s); sub(/",?[ \t]*$/, "", s); gsub(/\\"/, "\"", s); gsub(/\\\\/, "\\", s); return s }
/^[ \t]*"directory": "/ { d = val($0) }
/^[ \t]*"file": "/ { f = val($0) }
/^[ \t]*"output": "/ { o = val($0) }
/^[ \t]*}/ {
  # platform: CMake may write the object absolute; Ninja names it relative to the build directory
  if (d != "" && substr(o, 1, length(d) + 1) == d "/") o = substr(o, length(d) + 2)
  if (f != "" && o != "") print o "\t" f; d = ""; f = ""; o = ""
}
' "$2/compile_commands.json" > "$3/units.tsv"
[ -s "$3/units.tsv" ] || die "compile_commands.json in $2 lists no compile with an output"
while IFS="$TAB" read -r obj src; do
  [ -f "$2/$obj" ] && printf '%s\tbuilt\n' "$obj" || printf '%s\tmissing\n' "$obj"
done < "$3/units.tsv" > "$3/objects.tsv"

LC_ALL=C awk -F '\t' -v out="$3" '
function q(s,   r) { r = s; if (match(r, /'\''[^'\'']*'\''/)) return substr(r, RSTART + 1, RLENGTH - 2); return "" }
function classify(msg) {
  kind = "other"; sym = msg
  if (msg ~ /use of undeclared identifier/) { kind = "undeclared-identifier"; sym = q(msg) }
  else if (msg ~ /unknown type name|cannot find interface declaration for|cannot find protocol declaration for|unknown receiver/) { kind = "unknown-type"; sym = q(msg) }
  else if (msg ~ /file not found/) { kind = "missing-header"; sym = q(msg) }
  else if (msg ~ /no known (class|instance) method for selector/) { kind = "no-method"; sym = q(msg) }
  else if (msg ~ /declares the selector/) { kind = "no-method"; s = msg; sub(/.*declares the selector /, "", s); sym = q(s) }
  else if (msg ~ /property .* not found on object of type/) { kind = "no-method"; sym = q(msg) }
  else if (msg ~ /is unavailable/) { kind = "unavailable"; sym = q(msg) }
  sub(/^[+-]/, "", sym)
  if (sym == "") sym = msg
  gsub(/\t/, " ", sym)
}
function note(k, s) { key = k "\t" s; if (!((key, cur) in seen)) { seen[key, cur] = 1; files[key]++ } }
FILENAME ~ /census-targets\.tsv$/ { tname[$1] = $2; next }
FILENAME ~ /units\.tsv$/ { src[$1] = $2; order[++n] = $1; next }
FILENAME ~ /objects\.tsv$/ { built[$1] = ($2 == "built"); next }
/^FAILED: / { cur = $0; sub(/^FAILED: (\[code=[0-9]+\] )?/, "", cur); sub(/[ \t]+$/, "", cur); failed[cur] = 1; next }
/^\[[0-9]+\/[0-9]+\] / { cur = $0; if (!sub(/^\[[0-9]+\/[0-9]+\] Building [A-Za-z+]+ object /, "", cur)) cur = ""; sub(/[ \t]+$/, "", cur); next }
/: (fatal )?error: / {
  if (cur == "") next
  msg = $0; sub(/.*: (fatal )?error: /, "", msg); sub(/ \[-W[^]]*\]$/, "", msg)
  classify(msg)
  if (!(cur in first)) first[cur] = kind "\t" sym
  note(kind, sym)
  next
}
/: warning: (class|instance) method .* not found/ {
  if (cur == "") next
  msg = $0; sub(/.*: warning: /, "", msg); sub(/^(class|instance) method /, "", msg)
  sym = q(msg); sub(/^[+-]/, "", sym); note("no-method-warning", sym)
}
END {
  print "target\tfile\tstatus\tfirst_error_kind\tfirst_error_symbol" > (out "/census.tsv")
  bad = 0
  for (i = 1; i <= n; i++) {
    o = order[i]; p = o
    if (!sub(/^CMakeFiles\/census_/, "", p) || !sub(/\.dir\/.*/, "", p) || !(p in tname)) { print o > (out "/never-compiled"); bad++; continue }
    t = tname[p]; compiled[t]++
    if (!(t in seen_t)) { seen_t[t] = 1; tord[++m] = t }
    if (o in failed) { err[t]++; print t "\t" src[o] "\terror\t" (o in first ? first[o] : "other\t(no diagnostic in the log)") > (out "/census.tsv") }
    else if (built[o]) { ok[t]++; print t "\t" src[o] "\tok\t\t" > (out "/census.tsv") }
    else { print src[o] > (out "/never-compiled"); bad++ }
  }
  print "target\tcompiled\tok\terror" > (out "/summary.tsv")
  for (j = 1; j <= m; j++) { t = tord[j]; print t "\t" compiled[t] "\t" (ok[t] + 0) "\t" (err[t] + 0) > (out "/summary.tsv") }
  for (k in files) print k "\t" files[k] > (out "/symbols.body")
}' "$2/census-targets.tsv" "$3/units.tsv" "$3/objects.tsv" "$1"
rm -f "$3/units.tsv" "$3/objects.tsv"
if [ -s "$3/never-compiled" ]; then
  rm -f "$3/census.tsv" "$3/summary.tsv" "$3/symbols.body"
  die "$(wc -l < "$3/never-compiled" | tr -d ' ') source(s) were never compiled (no object, no FAILED: line); see $3/never-compiled and the build log"
fi
{ printf 'kind\tsymbol\tfiles\n'; [ -f "$3/symbols.body" ] && LC_ALL=C sort -t "$TAB" -k3,3nr -k1,1 -k2,2 "$3/symbols.body"; } > "$3/symbols.tsv"
rm -f "$3/symbols.body"
