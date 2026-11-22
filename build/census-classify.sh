#!/bin/sh
# platform: host-agnostic
#   usage: census-classify.sh BUILD_LOG SOURCES_TSV OUT_DIR
#          Reads a census's Ninja log (-k 0) and its "<target>\t<source>" list, and writes:
#            census.tsv   target file status(ok|error) first_error_kind first_error_symbol
#            summary.tsv  target compiled ok error
#            symbols.tsv  kind symbol files   (sorted by files, most first)
#          A failed source's diagnostics are those under its Ninja FAILED: line; its first error decides its
#          kind. Kinds: undeclared-identifier, unknown-type, missing-header, no-method, unavailable, other;
#          no-method-warning is a missing selector that only warned (MRC), still a runtime gap. symbols.tsv
#          counts distinct sources per symbol, so one gap that breaks many files is one row.
# spec: BUILD.md "Census"
set -eu
[ "$#" -eq 3 ] || { echo 'usage: census-classify.sh BUILD_LOG SOURCES_TSV OUT_DIR' >&2; exit 2; }
[ -f "$1" ] || { echo "census-classify: no log $1" >&2; exit 1; }
[ -f "$2" ] || { echo "census-classify: no source list $2" >&2; exit 1; }
LC_ALL=C awk -F '\t' -v out="$3" '
function q(s,   r) { r = s; if (match(r, /'\''[^'\'']*'\''/)) return substr(r, RSTART + 1, RLENGTH - 2); return "" }
function classify(msg) {
  kind = "other"; sym = msg
  if (msg ~ /use of undeclared identifier/) { kind = "undeclared-identifier"; sym = q(msg) }
  else if (msg ~ /unknown type name|cannot find interface declaration for|unknown receiver/) { kind = "unknown-type"; sym = q(msg) }
  else if (msg ~ /file not found/) { kind = "missing-header"; sym = q(msg) }
  else if (msg ~ /no known (class|instance) method for selector/) { kind = "no-method"; sym = q(msg) }
  else if (msg ~ /declares the selector/) { kind = "no-method"; s = msg; sub(/.*declares the selector /, "", s); sym = q(s) }
  else if (msg ~ /property .* not found on object of type/) { kind = "no-method"; sym = q(msg) }
  else if (msg ~ /is unavailable/) { kind = "unavailable"; sym = q(msg) }
  sub(/^[+-]/, "", sym)
  if (sym == "") sym = msg
  gsub(/\t/, " ", sym)
}
FNR == NR { tgt[$2] = $1; order[++n] = $2; next }
/^FAILED: / { cur = ""; want_cmd = 1; next }
want_cmd { want_cmd = 0; if (match($0, / -c [^ ]+/)) { cur = substr($0, RSTART + 4, RLENGTH - 4); failed[cur] = 1 } ; next }
/^\[[0-9]+\/[0-9]+\] / { cur = ""; next }
/: (fatal )?error: / {
  msg = $0; sub(/.*: (fatal )?error: /, "", msg); sub(/ \[-W[^]]*\]$/, "", msg)
  classify(msg)
  if (cur != "") {
    if (!(cur in first)) { first[cur] = kind "\t" sym }
    key = kind "\t" sym; if (!((key, cur) in seen)) { seen[key, cur] = 1; files[key]++ }
  }
  next
}
/: warning: (class|instance) method .* not found/ {
  path = $0; sub(/:[0-9]+:[0-9]+: warning: .*/, "", path)
  msg = $0; sub(/.*: warning: /, "", msg); classify(msg)
  s = msg; sub(/^(class|instance) method /, "", s); sym = q(s); sub(/^[+-]/, "", sym)
  key = "no-method-warning\t" sym; if (!((key, path) in seen)) { seen[key, path] = 1; files[key]++ }
}
END {
  print "target\tfile\tstatus\tfirst_error_kind\tfirst_error_symbol" > (out "/census.tsv")
  for (i = 1; i <= n; i++) {
    f = order[i]; t = tgt[f]; compiled[t]++
    if (!(t in seen_t)) { seen_t[t] = 1; tord[++m] = t }
    if (f in failed) { err[t]++; print t "\t" f "\terror\t" (f in first ? first[f] : "other\t(no diagnostic in the log)") > (out "/census.tsv") }
    else { ok[t]++; print t "\t" f "\tok\t\t" > (out "/census.tsv") }
  }
  print "target\tcompiled\tok\terror" > (out "/summary.tsv")
  for (j = 1; j <= m; j++) { t = tord[j]; print t "\t" compiled[t] "\t" (ok[t] + 0) "\t" (err[t] + 0) > (out "/summary.tsv") }
  for (k in files) print k "\t" files[k] > (out "/symbols.body")
}' "$2" "$1"
{ printf 'kind\tsymbol\tfiles\n'; [ -f "$3/symbols.body" ] && LC_ALL=C sort -t "$(printf '\t')" -k3,3nr -k1,1 -k2,2 "$3/symbols.body"; } > "$3/symbols.tsv"
rm -f "$3/symbols.body"
