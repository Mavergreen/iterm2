// Mavericks iTerm2: the family updater's post-update helper (POST_UPDATE_HELPER). It plays the part
// of upstream's in-app Sparkle once a new version is installed: it posts Sparkle's will-restart
// notification, which patch 0004 has the app hear on the distributed center, and waits for the app to
// acknowledge it (or, after 5 s without that, leaves it running, since quitting it then would be an
// ordinary quit). Then it quits every running instance through its own applicationShouldTerminate:
// and waits, as Sparkle's relauncher did, for them to exit. If a quit is declined, the app says so and
// the helper stops, leaving it running. Once all have exited it opens the installed app,
// /Applications/Mavericks iTerm2.app, or by bundle id if that is gone. With no instance running, it
// does nothing.

#import <Cocoa/Cocoa.h>

static NSString *const kAppBundleId = @"dev.mavergreen.iterm2.app";
static NSString *const kInstalledApp = @"/Applications/Mavericks iTerm2.app";

static BOOL gAcknowledged;
static BOOL gDeclined;

@interface iTermRestartReplies : NSObject
@end

@implementation iTermRestartReplies
- (void)acknowledged:(NSNotification *)notification {
    gAcknowledged = YES;
}
- (void)declined:(NSNotification *)notification {
    gDeclined = YES;
}
@end

static void spin(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

static BOOL anyRunning(NSArray *apps) {
    for (NSRunningApplication *app in apps) {
        if (![app isTerminated]) {
            return YES;
        }
    }
    return NO;
}

int main(void) {
    @autoreleasepool {
        NSArray *running = [NSRunningApplication runningApplicationsWithBundleIdentifier:kAppBundleId];
        if (running.count == 0) {
            return 0;
        }
        NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
        iTermRestartReplies *replies = [[[iTermRestartReplies alloc] init] autorelease];
        [center addObserver:replies selector:@selector(acknowledged:) name:@"MavericksiTerm2WillRestartAcknowledged" object:nil];
        [center addObserver:replies selector:@selector(declined:) name:@"MavericksiTerm2RestartDeclined" object:nil];
        [center postNotificationName:@"SUUpdaterWillRestartNotificationName" object:nil userInfo:nil deliverImmediately:YES];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
        while (!gAcknowledged && [deadline timeIntervalSinceNow] > 0) {
            spin();
        }
        if (!gAcknowledged) {
            NSLog(@"restart-for-update: iTerm2 did not acknowledge the update; quit and reopen it to use the new version");
            return 0;
        }
        for (NSRunningApplication *app in running) {
            [app terminate];
        }
        while (anyRunning(running) && !gDeclined) {
            spin();
        }
        if (gDeclined) {
            NSLog(@"restart-for-update: the quit was declined; the new version opens the next time iTerm2 does");
            return 0;
        }
        NSArray *args = [[NSFileManager defaultManager] fileExistsAtPath:kInstalledApp]
            ? [NSArray arrayWithObject:kInstalledApp]
            : [NSArray arrayWithObjects:@"-b", kAppBundleId, nil];
        NSTask *open = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:args];
        [open waitUntilExit];
        return 0;
    }
}
