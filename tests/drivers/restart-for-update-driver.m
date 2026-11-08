// spec: BUILD.md "Updates" -- the family updater restarts iTerm2 the way upstream's Sparkle did: its
//       helper posts Sparkle's will-restart notification, which the app now hears on the distributed
//       center, so a quit for an update leaves restorable sessions' jobs running, whatever the
//       kill-on-quit setting; and a notification no quit follows stops counting after a while.
#import "driver.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"

@interface iTermApplicationDelegate (DriverPrivate)
- (void)observeUpdateRestarts;
- (void)latchUpdateRestartIfPending;
- (void)updateRestartWasDeclined;
@end

static BOOL gAcknowledged;
static BOOL gDeclined;

@interface DriverAckObserver : NSObject
@end
@implementation DriverAckObserver
- (void)acknowledged:(NSNotification *)notification { gAcknowledged = YES; }
- (void)declined:(NSNotification *)notification { gDeclined = YES; }
@end

@interface iTermController (DriverPrivate)
- (BOOL)shouldLeaveSessionsRunningOnQuit;
@end

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

DRIVER_MAIN({
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[ @"RunJobsInServers", @"RestoreWindowContents", @"KillJobsInServersOnQuit",
                             @"NSQuitAlwaysKeepsWindows" ]) {
        [defaults setBool:YES forKey:key];
    }
    [defaults setBool:NO forKey:@"OpenArrangementAtStartup"];
    [defaults setBool:NO forKey:@"OpenNoWindowsAtStartup"];
    [defaults setDouble:1.0 forKey:@"MavericksiTerm2UpdateRestartSeconds"];

    iTermApplication *app = (iTermApplication *)[iTermApplication sharedApplication];
    iTermApplicationDelegate *delegate = [[[iTermApplicationDelegate alloc] init] autorelease];
    app.delegate = delegate;
    [delegate observeUpdateRestarts];
    DriverAckObserver *ack = [[[DriverAckObserver alloc] init] autorelease];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:ack
                                                        selector:@selector(acknowledged:)
                                                            name:@"MavericksiTerm2WillRestartAcknowledged"
                                                          object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:ack
                                                        selector:@selector(declined:)
                                                            name:@"MavericksiTerm2RestartDeclined"
                                                          object:nil];

    DRIVER_EXPECT(!delegate.sparkleRestarting, "restart for update: not restarting at first");
    DRIVER_EXPECT(![[iTermController sharedInstance] shouldLeaveSessionsRunningOnQuit],
                  "restart for update: an ordinary quit kills server jobs when the setting says so");

    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"SUUpdaterWillRestartNotificationName"
                                                                   object:nil
                                                                 userInfo:nil
                                                       deliverImmediately:YES];
    spin(0.5);
    DRIVER_EXPECT(delegate.sparkleRestarting, "restart for update: Sparkle's notification arrives from another process's center");
    DRIVER_EXPECT([[iTermController sharedInstance] shouldLeaveSessionsRunningOnQuit],
                  "restart for update: a quit for an update leaves restorable sessions' jobs running");

    DRIVER_EXPECT(gAcknowledged, "restart for update: the app acknowledges the notification, so the helper may quit it");

    spin(1.0);
    DRIVER_EXPECT(!delegate.sparkleRestarting, "restart for update: a notification no quit follows stops counting");
    DRIVER_EXPECT(![[iTermController sharedInstance] shouldLeaveSessionsRunningOnQuit],
                  "restart for update: after that, an ordinary quit kills server jobs again");

    // A quit for an update that has begun keeps its decision however long its prompt stays open.
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"SUUpdaterWillRestartNotificationName"
                                                                   object:nil
                                                                 userInfo:nil
                                                       deliverImmediately:YES];
    spin(0.5);
    [delegate latchUpdateRestartIfPending];
    spin(1.0);
    DRIVER_EXPECT(delegate.sparkleRestarting && [[iTermController sharedInstance] shouldLeaveSessionsRunningOnQuit],
                  "restart for update: a quit begun within the window keeps leaving jobs running past it");

    // A declined quit ends the update's restart, and tells the helper, which stops waiting.
    [delegate updateRestartWasDeclined];
    spin(0.5);
    DRIVER_EXPECT(!delegate.sparkleRestarting && ![[iTermController sharedInstance] shouldLeaveSessionsRunningOnQuit],
                  "restart for update: a declined quit clears the restart, latched or not");
    DRIVER_EXPECT(gDeclined, "restart for update: a declined quit tells the helper");
    for (NSString *key in @[ @"RunJobsInServers", @"RestoreWindowContents", @"KillJobsInServersOnQuit",
                             @"NSQuitAlwaysKeepsWindows", @"OpenArrangementAtStartup", @"OpenNoWindowsAtStartup",
                             @"MavericksiTerm2UpdateRestartSeconds" ]) {
        [defaults removeObjectForKey:key];
    }
})
