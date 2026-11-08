// spec: BUILD.md "Build evidence" -- the tmux drivers stand in for the terminal session: every string the
//       gateway would write to tmux is kept, in order, for the driver to inspect.
#import "TmuxGateway.h"

@interface FakeTmuxSession : NSObject <TmuxGatewayDelegate>
@property(nonatomic, readonly) NSMutableArray<NSString *> *written;
@property(nonatomic, assign) TmuxController *controller;
@end
