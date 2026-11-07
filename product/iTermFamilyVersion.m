// Mavericks iTerm2: the version comparison iTerm2's incompatible-software checks used from Sparkle
// (patch 0004 removes Sparkle). Dotted numbers compare numerically, a missing component counting as 0;
// at equal numbers, a version with a suffix ("6.6.2b1", "7.3.3 (beta)") is a prerelease, older than
// the plain release, and two suffixes compare numerically. tests/version-compare-test.sh pins this.

#import <Foundation/Foundation.h>

BOOL iTermFamilyVersionIsNewer(NSString *version, NSString *other);

static void iTermFamilyVersionSplit(NSString *version, NSArray **numbers, NSString **suffix) {
    NSScanner *scanner = [NSScanner scannerWithString:version];
    NSMutableArray *parts = [NSMutableArray array];
    NSInteger n;
    while ([scanner scanInteger:&n]) {
        [parts addObject:@(n)];
        NSUInteger mark = scanner.scanLocation;
        if (![scanner scanString:@"." intoString:NULL]) {
            break;
        }
        NSInteger peek;
        if (![[NSScanner scannerWithString:[version substringFromIndex:scanner.scanLocation]] scanInteger:&peek]) {
            scanner.scanLocation = mark;
            break;
        }
    }
    *numbers = parts;
    *suffix = [[version substringFromIndex:scanner.scanLocation]
                  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

BOOL iTermFamilyVersionIsNewer(NSString *version, NSString *other) {
    if (!version.length || !other.length) {
        return NO;
    }
    NSArray *a, *b;
    NSString *sa, *sb;
    iTermFamilyVersionSplit(version, &a, &sa);
    iTermFamilyVersionSplit(other, &b, &sb);
    NSUInteger count = MAX(a.count, b.count);
    for (NSUInteger i = 0; i < count; i++) {
        NSInteger x = i < a.count ? [a[i] integerValue] : 0;
        NSInteger y = i < b.count ? [b[i] integerValue] : 0;
        if (x != y) {
            return x > y;
        }
    }
    if (!sa.length || !sb.length) {
        return !sa.length && sb.length;
    }
    return [sa compare:sb options:NSNumericSearch] == NSOrderedDescending;
}
