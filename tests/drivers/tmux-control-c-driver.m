// spec: SECURITY.md CVE-2023-46300 -- when tmux integration starts, the first thing sent is Control-C, so a
//       command left typed at the prompt before integration began is cancelled, not run.
#import "driver.h"
#import "fake-tmux.h"
#import "TmuxController.h"

DRIVER_MAIN({
    FakeTmuxSession *session = [[[FakeTmuxSession alloc] init] autorelease];
    TmuxGateway *gateway = [[[TmuxGateway alloc] initWithDelegate:session] autorelease];
    TmuxController *controller = [[[TmuxController alloc] initWithGateway:gateway clientName:@"driver"] autorelease];
    session.controller = controller;
    [controller sendControlC];
    NSString *all = [session.written componentsJoinedByString:@""];
    DRIVER_EXPECT(all.length > 0 && [all characterAtIndex:0] == 0x03, "control-c: the first byte written is 0x03");
    DRIVER_EXPECT([all isEqualToString:@"\x03phony-command\r"], "control-c: then phony-command and the command's end");
})
