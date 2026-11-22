// spec: SMOKE.md check 8 -- a failed scp transfer says why where people look: the failure notification's body
//       carries the transfer's error, not only its title, so the reason is no longer only in Console.
#import <objc/runtime.h>
#import "driver.h"
#import "SCPFile.h"
#import "iTermGrowlDelegate.h"

static NSMutableArray *notified;

static void record(id self, SEL _cmd, NSString *title, NSString *description) {
    [notified addObject:@[ title ?: @"", description ?: @"" ]];
}

static NSArray *transfer(BOOL download) {
    [notified removeAllObjects];
    SCPFile *file = [[[SCPFile alloc] init] autorelease];
    SCPPath *path = [[[SCPPath alloc] init] autorelease];
    path.path = @"/etc/motd";
    path.hostname = @"example.invalid";
    path.username = @"driver";
    file.path = path;
    file.localPath = @"/tmp/motd";
    if (download) {
        [file download];
    } else {
        [file upload];
    }
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (file.status != kTransferrableFileStatusFinishedWithError && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    DRIVER_EXPECT(file.status == kTransferrableFileStatusFinishedWithError,
                  download ? "scp download: finishes with an error" : "scp upload: finishes with an error");
    return @[ file.error ?: @"", [[notified copy] autorelease] ];
}

DRIVER_MAIN({
    notified = [NSMutableArray array];
    Method m = class_getInstanceMethod([iTermGrowlDelegate class], @selector(growlNotify:withDescription:));
    method_setImplementation(m, (IMP)record);

    for (NSNumber *download in @[ @YES, @NO ]) {
        NSArray *result = transfer(download.boolValue);
        NSString *error = result[0];
        NSArray *notes = result[1];
        BOOL d = download.boolValue;
        DRIVER_EXPECT([error rangeOfString:@"CVE-2019-3855"].location != NSNotFound,
                      d ? "scp download: the error names why scp is unavailable"
                        : "scp upload: the error names why scp is unavailable");
        DRIVER_EXPECT(notes.count == 1,
                      d ? "scp download: one notification" : "scp upload: one notification");
        NSArray *note = notes.firstObject;
        DRIVER_EXPECT([note[0] hasSuffix:@"failed."],
                      d ? "scp download: the notification's title says it failed"
                        : "scp upload: the notification's title says it failed");
        DRIVER_EXPECT([note[1] isEqualToString:error],
                      d ? "scp download: the notification's body is the error"
                        : "scp upload: the notification's body is the error");
    }
})
