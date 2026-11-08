#import "fake-tmux.h"

@implementation FakeTmuxSession

- (instancetype)init {
    self = [super init];
    if (self) {
        _written = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_written release];
    [super dealloc];
}

- (TmuxController *)tmuxController { return _controller; }
- (void)tmuxWriteString:(NSString *)string { [_written addObject:string]; }
- (void)tmuxUpdateLayoutForWindow:(int)windowId layout:(NSString *)layout zoomed:(NSNumber *)zoomed { }
- (void)tmuxWindowAddedWithId:(int)windowId { }
- (void)tmuxWindowClosedWithId:(int)windowId { }
- (void)tmuxWindowRenamedWithId:(int)windowId to:(NSString *)newName { }
- (void)tmuxHostDisconnected { }
- (void)tmuxReadTask:(NSData *)data { }
- (void)tmuxSessionChanged:(NSString *)sessionName sessionId:(int)sessionId { }
- (void)tmuxSessionsChanged { }
- (void)tmuxWindowsDidChange { }
- (void)tmuxSession:(int)sessionId renamed:(NSString *)newName { }
- (NSSize)tmuxBookmarkSize { return NSMakeSize(80, 25); }
- (NSInteger)tmuxNumHistoryLinesInBookmark { return 1000; }
- (void)tmuxSetSecureLogging:(BOOL)secureLogging { }
- (void)tmuxPrintLine:(NSString *)line { }
- (NSWindowController<iTermWindowController> *)tmuxGatewayWindow { return nil; }
- (void)tmuxInitialCommandDidCompleteSuccessfully { }
- (void)tmuxInitialCommandDidFailWithError:(NSString *)error { }
- (void)tmuxDidOpenInitialWindows { }

@end
