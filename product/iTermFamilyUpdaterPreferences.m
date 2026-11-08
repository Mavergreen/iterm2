// Mavericks iTerm2: General > "Check for updates automatically" is the family updater's own setting,
// SUEnableAutomaticChecks in its defaults domain (the updater's bundle id, from shipyard's registry as
// ITERM_UPDATER_BUNDLE_ID). Absent, the updater checks, as its AUTO_CHECK default says. Patch 0004
// binds the checkbox to these.

#import <Foundation/Foundation.h>

static CFStringRef const kAutomaticChecksKey = CFSTR("SUEnableAutomaticChecks");

NSString *iTermFamilyUpdaterBundleIdentifier(void) {
    return @ITERM_UPDATER_BUNDLE_ID;
}

BOOL iTermFamilyUpdaterChecksAutomatically(void) {
    CFStringRef domain = (CFStringRef)iTermFamilyUpdaterBundleIdentifier();
    CFPreferencesAppSynchronize(domain);
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue(kAutomaticChecksKey, domain, &valid);
    return valid ? (BOOL)value : YES;
}

void iTermSetFamilyUpdaterChecksAutomatically(BOOL checks) {
    CFStringRef domain = (CFStringRef)iTermFamilyUpdaterBundleIdentifier();
    CFPreferencesSetAppValue(kAutomaticChecksKey, checks ? kCFBooleanTrue : kCFBooleanFalse, domain);
    CFPreferencesAppSynchronize(domain);
}
