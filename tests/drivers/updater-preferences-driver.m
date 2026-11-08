// spec: BUILD.md "Updates" -- General > "Check for updates automatically" is the family updater's own
//       SUEnableAutomaticChecks, read and written in the updater's defaults domain, absent meaning on;
//       the app's own domain never holds it. The driver puts back whatever the domain held.
#import "driver.h"

NSString *iTermFamilyUpdaterBundleIdentifier(void);
BOOL iTermFamilyUpdaterChecksAutomatically(void);
void iTermSetFamilyUpdaterChecksAutomatically(BOOL checks);

static void setRaw(CFStringRef domain, id value) {
    CFPreferencesSetAppValue(CFSTR("SUEnableAutomaticChecks"), (CFPropertyListRef)value, domain);
    CFPreferencesAppSynchronize(domain);
}

DRIVER_MAIN({
    NSString *domain = iTermFamilyUpdaterBundleIdentifier();
    DRIVER_EXPECT([domain hasSuffix:@".updater"], "updater preferences: the domain is the updater's bundle id");
    CFStringRef d = (CFStringRef)domain;
    id saved = [(id)CFPreferencesCopyAppValue(CFSTR("SUEnableAutomaticChecks"), d) autorelease];

    setRaw(d, nil);
    DRIVER_EXPECT(iTermFamilyUpdaterChecksAutomatically(), "updater preferences: no setting means it checks");
    setRaw(d, @NO);
    DRIVER_EXPECT(!iTermFamilyUpdaterChecksAutomatically(), "updater preferences: the updater's NO reads as off");
    iTermSetFamilyUpdaterChecksAutomatically(YES);
    id now = [(id)CFPreferencesCopyAppValue(CFSTR("SUEnableAutomaticChecks"), d) autorelease];
    DRIVER_EXPECT([now isEqual:@YES], "updater preferences: turning it on writes YES to the updater's domain");
    iTermSetFamilyUpdaterChecksAutomatically(NO);
    now = [(id)CFPreferencesCopyAppValue(CFSTR("SUEnableAutomaticChecks"), d) autorelease];
    DRIVER_EXPECT([now isEqual:@NO], "updater preferences: turning it off writes NO to the updater's domain");
    DRIVER_EXPECT([[NSUserDefaults standardUserDefaults] objectForKey:@"SUEnableAutomaticChecks"] == nil,
                  "updater preferences: the app's own domain holds no such key");

    setRaw(d, saved);
})
