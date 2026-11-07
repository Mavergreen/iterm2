#!/bin/sh
# platform: macOS-only -- compiles product/iTermFamilyVersion.m with clang22 and runs it, so it needs a host
#           that runs x86_64: 10.9 natively, or a modern Mac with Rosetta (77 = skip without it).
# spec: BUILD.md "Updates" -- version:newerThan: replaced Sparkle's comparator for iTerm2's four
#       incompatible-software checks (Docker 1.3.0, LaunchBar 6.6.2, Path Finder 7.3.3, Tower 2.3.4).
#       Dotted numbers compare numerically; at equal numbers, a version with a suffix (6.6.2b1,
#       "7.3.3 (beta)") is a prerelease and older than the plain release, as Sparkle ordered them.
set -eu
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/iterm-version-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
. "$REPO_ROOT/build/msc.sh"
for c in /usr/local/mavergreen/clang22/bin/clang /usr/local/mavergreen/clang22-cross/bin/clang; do
  [ -x "$c" ] && CLANG22=$c && break
done
[ -n "${CLANG22:-}" ] || { echo "version-compare-test: no clang22" >&2; exit 1; }
if [ "$(uname -m)" != x86_64 ] && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "version-compare-test: SKIP: this host cannot run x86_64 (no Rosetta)"; exit 77
fi
cat > "$T/main.m" <<'M'
#import <Foundation/Foundation.h>
BOOL iTermFamilyVersionIsNewer(NSString *version, NSString *other);
int main(void) {
    @autoreleasepool {
        struct { const char *a, *b; BOOL want; } cases[] = {
            {"6.6.3", "6.6.2", YES}, {"6.6.2", "6.6.2", NO}, {"6.6.1", "6.6.2", NO},
            {"1.10", "1.9", YES}, {"2.3.4.1", "2.3.4", YES}, {"2.3.4", "2.3.4.0", NO},
            {"6.6.2b1", "6.6.2", NO}, {"6.6.2", "6.6.2b1", YES}, {"7.3.3 (beta)", "7.3.3", NO},
            {"6.6.2b2", "6.6.2b1", YES}, {"7.4b1", "7.3.3", YES}, {"", "1.0", NO},
        };
        int bad = 0;
        for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
            BOOL got = iTermFamilyVersionIsNewer(@(cases[i].a), @(cases[i].b));
            if (got != cases[i].want) {
                printf("FAIL: %s newer than %s: got %d, want %d\n", cases[i].a, cases[i].b, got, cases[i].want);
                bad++;
            }
        }
        if (iTermFamilyVersionIsNewer(nil, @"1.0") || iTermFamilyVersionIsNewer(@"1.0", nil)) {
            printf("FAIL: a nil version is newer\n"); bad++;
        }
        return bad ? 1 : 0;
    }
}
M
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
"$CLANG22" -x objective-c -fno-objc-arc -std=c99 -arch x86_64 -isysroot "$SDK" -mmacosx-version-min=10.9 -Werror \
  -o "$T/vc" "$T/main.m" "$REPO_ROOT/product/iTermFamilyVersion.m" -framework Foundation \
  || { echo "version-compare-test: FAIL: does not compile" >&2; exit 1; }
if [ "$(uname -m)" = x86_64 ]; then "$T/vc"; else /usr/bin/arch -x86_64 "$T/vc"; fi \
  || { echo "version-compare-test: FAIL" >&2; exit 1; }
echo "version-compare-test: OK"
