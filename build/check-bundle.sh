#!/bin/sh
# platform: macOS-only -- reads Info.plist with plutil and load commands with otool.
#   usage: check-bundle.sh APP SOURCE_DIR
#          Refuses (exit 1, naming each problem) an assembled iTerm2 bundle that is not exactly what the
#          explicit inputs make: every resources/compiled.tsv member at its size and SHA-256 (29 nibs and
#          the compiled model); every resources/app-resources.tsv file byte-identical to the prepared
#          source SOURCE_DIR; image_decoder in Resources, mode 0755, with image_decoder.sb; iTerm2.icns;
#          Info.plist with the Mavergreen identity, the 10.9 floor, a -mavericks.N version and its
#          dotted comparison key, upstream's nib/class/scripting fields, and no SU* key; PkgInfo; no
#          executable or Mach-O but MacOS/iTerm2, MacOS/restart-for-update, Resources/image_decoder and the
#          rebuilt ColorPicker
#          (never the prebuilt one in SOURCE_DIR); no Growl, NMSSH or Sparkle file or load command.
#          OTOOL and NM name the readers (default: clang22's llvm-otool and llvm-nm); a read that fails
#          refuses the bundle, and so does an undefined Growl, NMSSH, libssh2 or SU* class symbol.
# spec: BUILD.md "Resources and the bundle".
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
[ "$#" -eq 2 ] || { echo 'usage: check-bundle.sh APP SOURCE_DIR' >&2; exit 2; }
APP=$1; SRC=$2; C="$APP/Contents"
problems=0
bad() { echo "check-bundle: $*" >&2; problems=$((problems + 1)); }
TAB=$(printf '\t')
. "$REPO_ROOT/build/msc.sh"
. "$SHIPYARD_SCRIPTS/lib/vercmp.sh"
# platform: 10.9 without the Command Line Tools has only a stub /usr/bin/otool, and a reader that cannot
#           run prints nothing to search; so the readers default to clang22's own, and every read must
#           succeed and name the file, or the bundle is refused rather than passed unread
for t in OTOOL:llvm-otool NM:llvm-nm; do
  var=${t%%:*}
  eval "cur=\${$var:-}"
  if [ -z "$cur" ]; then
    for d in /usr/local/mavergreen/clang22/bin /usr/local/mavergreen/clang22-cross/bin; do
      [ -x "$d/${t#*:}" ] && cur="$d/${t#*:}" && break
    done
  fi
  eval "$var=\${cur:-/nonexistent/${t#*:}}"
done

[ "$(ls "$C/MacOS" 2>/dev/null | tr '\n' ' ')" = 'iTerm2 restart-for-update ' ] \
  || bad "Contents/MacOS is not exactly iTerm2 and restart-for-update: $(ls "$C/MacOS" 2>/dev/null | tr '\n' ' ')"
[ "$(ls "$C/Frameworks" 2>/dev/null)" = ColorPicker.framework ] \
  || bad "Contents/Frameworks is not exactly ColorPicker.framework: $(ls "$C/Frameworks" 2>/dev/null | tr '\n' ' ')"
cp_bin="$C/Frameworks/ColorPicker.framework/Versions/A/ColorPicker"
[ -f "$cp_bin" ] || bad "no rebuilt ColorPicker binary"
if [ -f "$cp_bin" ] && cmp -s "$cp_bin" "$SRC/ColorPicker/ColorPicker.framework/Versions/A/ColorPicker"; then
  bad "ColorPicker is the prebuilt framework from the source archive, not the rebuilt one"
fi

tail -n +2 "$REPO_ROOT/resources/compiled.tsv" | while IFS="$TAB" read -r member dest kind bytes sha; do
  f="$C/Resources/$dest"
  if [ ! -f "$f" ]; then echo "missing compiled resource $dest"
  elif [ "$(wc -c < "$f" | tr -d ' ')" != "$bytes" ] || [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" != "$sha" ]; then
    echo "compiled resource $dest is not the measured $bytes bytes / $sha"
  fi
done > "$APP.check.$$" || :
tail -n +2 "$REPO_ROOT/resources/app-resources.tsv" | while IFS="$TAB" read -r s d; do
  cmp -s "$SRC/$s" "$C/Resources/$d" || echo "resource $d is missing or is not $s"
done >> "$APP.check.$$" || :
while IFS= read -r line; do bad "$line"; done < "$APP.check.$$"
rm -f "$APP.check.$$"

[ "$(ls -l "$C/Resources/image_decoder" 2>/dev/null | cut -c1-10)" = -rwxr-xr-x ] \
  || bad "Resources/image_decoder is missing or not 0755 (iTermImageDecoderDriver.m finds it with pathForResource)"
cmp -s "$SRC/OtherResources/image_decoder.sb" "$C/Resources/image_decoder.sb" || bad "Resources/image_decoder.sb is missing or not upstream's"
[ -s "$C/Resources/iTerm2.icns" ] || bad "no Resources/iTerm2.icns"
[ "$(cat "$C/PkgInfo" 2>/dev/null)" = APPLITRM ] || bad "PkgInfo is not APPLITRM"

p() { plutil -extract "$1" xml1 -o - "$C/Info.plist" 2>/dev/null | sed -n 's:.*<string>\(.*\)</string>.*:\1:p'; }
[ "$(p CFBundleIdentifier)" = dev.mavergreen.iterm2.app ] || bad "CFBundleIdentifier is '$(p CFBundleIdentifier)'"
[ "$(p CFBundleDisplayName)" = "Mavericks iTerm2" ] && [ "$(p CFBundleName)" = "Mavericks iTerm2" ] \
  || bad "CFBundleName/CFBundleDisplayName are not Mavericks iTerm2"
[ "$(p CFBundleExecutable)" = iTerm2 ] || bad "CFBundleExecutable is not iTerm2"
[ "$(p LSMinimumSystemVersion)" = 10.9 ] || bad "LSMinimumSystemVersion is not 10.9"
short=$(p CFBundleShortVersionString)
printf '%s\n' "$short" | grep -Eqx '[0-9]+(\.[0-9]+)*-mavericks\.[1-9][0-9]*' || bad "CFBundleShortVersionString '$short' is not <upstream>-mavericks.N"
[ "$(p CFBundleVersion)" = "$(comparison_key "$short" 2>/dev/null)" ] || bad "CFBundleVersion is not the comparison key of $short"
[ "$(p NSMainNibFile)" = MainMenu ] && [ "$(p NSPrincipalClass)" = iTermApplication ] \
  && [ "$(p OSAScriptingDefinition)" = iTerm2.sdef ] && [ "$(p CFBundleIconFile)" = iTerm2.icns ] \
  || bad "Info.plist lost an upstream field (NSMainNibFile, NSPrincipalClass, OSAScriptingDefinition, CFBundleIconFile)"
plutil -convert xml1 -o - "$C/Info.plist" 2>/dev/null | grep -q '<key>SU' && bad "Info.plist has an SU* (Sparkle) key"

dropped=$(cd "$APP" && find . | grep -iE 'growl|sparkle|nmssh|libssh2|dsa_pub|\.xib$|\.xcassets' || :)
[ -z "$dropped" ] || bad "a dropped or source-only file is in the bundle: $(echo $dropped)"
macho=$(cd "$APP" && find . -type f | while IFS= read -r f; do
  case "$(file -b "$f")" in (*Mach-O*) echo "$f" ;; (*) [ -x "$f" ] && echo "$f" ;; esac
done | sort)
allowed='./Contents/Frameworks/ColorPicker.framework/Versions/A/ColorPicker
./Contents/MacOS/iTerm2
./Contents/MacOS/restart-for-update
./Contents/Resources/image_decoder'
[ "$macho" = "$allowed" ] || bad "executables and Mach-O files are not exactly the four allowed: $(echo $macho)"
for f in $macho; do
  case "$f" in ./*) ;; *) continue ;; esac
  if ! "$OTOOL" -L "$APP/$f" > "$APP.otool.$$" 2>/dev/null || ! grep -qF "$APP/$f" "$APP.otool.$$"; then
    echo "$OTOOL could not read the load commands of $f"
  else
    grep -iE 'growl|sparkle|nmssh|libssh2' "$APP.otool.$$" | while IFS= read -r l; do echo "$f loads $l"; done
  fi
  # spec: BUILD.md "Resources and the bundle" -- every run-path search stays inside the bundle: an absolute
  #       LC_RPATH names a directory of the build host that dyld would search on the user's Mac
  if ! "$OTOOL" -l "$APP/$f" > "$APP.otool.$$" 2>/dev/null; then
    echo "$OTOOL could not read the run paths of $f"
  else
    awk '$2 == "LC_RPATH" { r = 1; next } r && $1 == "path" { print $2; r = 0 }' "$APP.otool.$$" \
      | grep -v '^@' | while IFS= read -r p; do echo "$f searches $p, outside the bundle"; done
  fi
  # spec: BUILD.md "Dependency dispositions" -- no symbol of a dropped framework may remain referenced; the
  #       nib shim defines its own SUUpdater, so a defined SUUpdater is not a reference
  if ! "$NM" -u "$APP/$f" > "$APP.otool.$$" 2>/dev/null; then
    echo "$NM could not read the undefined symbols of $f"
  else
    grep -iE 'growl|nmssh|libssh2|_OBJC_CLASS_\$_SU[A-Z]' "$APP.otool.$$" | while IFS= read -r s; do echo "$f references $s"; done
  fi
  rm -f "$APP.otool.$$"
done > "$APP.check.$$" || :
while IFS= read -r line; do bad "$line"; done < "$APP.check.$$"
rm -f "$APP.check.$$"

[ "$problems" -eq 0 ] || { echo "check-bundle: $APP refused ($problems problem(s))" >&2; exit 1; }
echo "check-bundle: $APP OK"
