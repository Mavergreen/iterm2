// spec: BUILD.md "Build evidence" -- the harness links and runs: a gateway built from the shipped sources
//       writes a command to its session as tmux control mode expects it (ended by a carriage return).
#import "driver.h"
#import "fake-tmux.h"

DRIVER_MAIN({
    FakeTmuxSession *session = [[[FakeTmuxSession alloc] init] autorelease];
    TmuxGateway *gateway = [[[TmuxGateway alloc] initWithDelegate:session] autorelease];
    DRIVER_EXPECT(gateway.delegate == session, "smoke: the gateway keeps its session");
    [gateway sendCommand:@"list-sessions" responseTarget:nil responseSelector:NULL];
    DRIVER_EXPECT([[session.written componentsJoinedByString:@""] isEqualToString:@"list-sessions\r"],
                  "smoke: a command reaches the session, ended by a carriage return");
})
