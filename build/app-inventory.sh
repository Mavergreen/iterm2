#!/bin/sh
# platform: host-agnostic -- reads Mach-O with clang22's llvm-otool, llvm-nm and llvm-lipo (OTOOL, NM, LIPO), never Xcode's
#   usage: app-inventory.sh APP
#          Prints APP's inventory in a form a native and a cross build of one commit can be compared by:
#          every file's path, sorted, and for each slice of each Mach-O a line naming its arch, with
#          digests of its load commands (kinds, linked dylibs, rpaths and minimum OS; offsets, sizes and
#          UUIDs are left out, as they follow from the bytes), of its undefined symbols, and of its
#          defined external symbols.
set -eu
[ "$#" -eq 1 ] && [ -d "$1" ] || { echo 'usage: app-inventory.sh APP' >&2; exit 2; }
APP=$(CDPATH= cd "$1" && pwd)
for t in OTOOL:llvm-otool NM:llvm-nm LIPO:llvm-lipo; do
  var=${t%%:*}
  eval "cur=\${$var:-}"
  if [ -z "$cur" ]; then
    for d in /usr/local/mavergreen/clang22/bin /usr/local/mavergreen/clang22-cross/bin; do
      [ -x "$d/${t#*:}" ] && cur="$d/${t#*:}" && break
    done
  fi
  [ -n "$cur" ] || { echo "app-inventory: no ${t#*:}; set $var" >&2; exit 1; }
  eval "$var=\$cur"
done
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -c1-16; else sha256sum | cut -c1-16; fi; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/app-inventory.XXXXXX")   # platform: 10.9 BSD mktemp requires a template
trap 'rm -rf "$tmp"' EXIT
cd "$APP"
find . \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r f; do
  printf 'file %s\n' "$f"
  [ -L "$f" ] && continue
  case "$(od -An -tx1 -N4 "$f" 2>/dev/null | tr -d ' \n')" in
    cffaedfe|cefaedfe|feedfacf|feedface|cafebabe) ;;
    *) continue ;;
  esac
  # platform: a reader given a universal file reads the host's own slice, so each slice is thinned out
  #           and read on its own, the same on every host
  for arch in $("$LIPO" -archs "$f"); do
    if [ "$("$LIPO" -archs "$f" | wc -w | tr -d ' ')" -gt 1 ]; then
      "$LIPO" -thin "$arch" "$f" -output "$tmp/slice" || exit 1
      s=$tmp/slice
    else
      s=$f
    fi
    lc=$("$OTOOL" -l "$s" | awk '
      $1 == "cmd" { print "cmd " $2; next }
      $1 == "name" || $1 == "path" { print $1 " " $2; next }
      $1 == "minos" || $1 == "version" || $1 == "sdk" { print $1 " " $2 }' | sha)
    und=$("$NM" -u "$s" 2>/dev/null | LC_ALL=C sort -u | sha)
    def=$("$NM" -gU "$s" 2>/dev/null | awk '{ print $NF }' | LC_ALL=C sort -u | sha)
    printf 'macho %s %s load=%s undefined=%s defined=%s\n' "$f" "$arch" "$lc" "$und" "$def"
  done
done
