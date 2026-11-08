// spec: BUILD.md "Identity and coexistence" -- the support directory is named by the app's CFBundleName;
//       with none (a bare executable such as this driver), there is no support directory, rather than
//       ~/Library/Application Support itself, where notes and scripts would land loose.
#import "driver.h"
#import "NSFileManager+iTerm.h"

DRIVER_MAIN({
    DRIVER_EXPECT([[NSBundle mainBundle] objectForInfoDictionaryKey:(id)kCFBundleNameKey] == nil,
                  "support directory: the driver has no CFBundleName");
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *support = [fileManager applicationSupportDirectory];
    NSString *legacy = [fileManager legacyApplicationSupportDirectory];
    printf("  support %s, legacy %s\n", support.UTF8String ?: "(none)", legacy.UTF8String ?: "(none)");
    DRIVER_EXPECT(support == nil, "support directory: none without a CFBundleName");
    DRIVER_EXPECT(legacy == nil, "support directory: no legacy one either");
})
