// spec: SECURITY.md CVE-2019-9535 -- a session name the tmux server sends never becomes part of a
//       command (sessions are targeted by number), and options this app stores in the server are written
//       hex-encoded, while values written by upstream iTerm2 or an older build are still read.
#import "driver.h"
#import "fake-tmux.h"
#import "TmuxController.h"
#import "EquivalenceClassSet.h"
#import "VT100Token.h"

@interface TmuxController (DriverPrivate)
- (void)listSessionsResponse:(NSString *)result;
- (void)getHiddenWindowsResponse:(NSString *)response;
- (void)getOriginsResponse:(NSString *)result;
- (void)getAffinitiesResponse:(NSString *)result;
- (void)saveHiddenWindows;
- (void)saveAffinities;
- (void)saveWindowOrigins;
@end

static NSString *hex(NSString *s) {
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableString *r = [NSMutableString string];
    for (NSUInteger i = 0; i < d.length; i++) {
        [r appendFormat:@"%02x", ((const unsigned char *)d.bytes)[i]];
    }
    return r;
}

static TmuxController *controllerFor(FakeTmuxSession *session) {
    TmuxGateway *gateway = [[[TmuxGateway alloc] initWithDelegate:session] autorelease];
    TmuxController *controller = [[[TmuxController alloc] initWithGateway:gateway clientName:@"driver"] autorelease];
    session.controller = controller;
    return controller;
}

// A line as tmux control mode sends it, through the gateway's own parser.
static void receive(TmuxController *controller, NSString *string) {
    VT100Token *line = [VT100Token token];
    line->type = TMUX_LINE;
    line.string = string;
    line.savedData = [string dataUsingEncoding:NSUTF8StringEncoding];
    [controller.gateway executeToken:line];
}

static BOOL targets(NSString *command, NSArray<NSString *> *verbs) {
    for (NSString *verb in verbs) {
        if ([command hasPrefix:verb]) {
            return YES;
        }
    }
    return NO;
}

DRIVER_MAIN({
    NSArray<NSString *> *names = @[ @"a\"; run-shell \"touch /tmp/pwned", @"x' ; kill-server '", @"#{pane_pid}",
                                    @"$(id)", @"two words", @"ünï" ];
    NSArray<NSString *> *verbs = @[ @"rename-session", @"kill-session", @"attach-session", @"link-window",
                                    @"list-windows", @"new-window", @"rename-window" ];
    for (NSString *name in names) {
        FakeTmuxSession *session = [[[FakeTmuxSession alloc] init] autorelease];
        TmuxController *controller = controllerFor(session);
        receive(controller, [NSString stringWithFormat:@"%%session-changed $7 %@", name]);
        DRIVER_EXPECT(controller.sessionId == 7 && [controller.sessionName isEqualToString:name],
                      "adversarial session names: %session-changed parses to the number and the whole name");
        [controller listSessionsResponse:[NSString stringWithFormat:@"$7 %@\n$8 other", name]];
        iTermTmuxSessionObject *first = controller.sessionObjects.firstObject;
        DRIVER_EXPECT(controller.sessionObjects.count == 2 && first.number == 7 && [first.name isEqualToString:name],
                      "adversarial session names: list-sessions gives each session's number and name");

        [controller renameSessionNumber:7 to:@"renamed"];
        [controller killSessionNumber:7];
        [controller attachToSessionWithNumber:7];
        [controller linkWindowId:3 inSessionNumber:7 toSessionNumber:8];
        [controller unlinkWindowWithId:3];
        [controller renameWindowWithId:3 inSessionNumber:@7 toName:@"w"];
        [controller newWindowInSessionNumber:@7];
        [controller listWindowsInSessionNumber:7 target:session selector:@selector(tmuxSessionsChanged) object:@7];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];

        BOOL allTarget7 = YES, nameAbsent = YES, noInjection = YES;
        NSUInteger targeted = 0;
        for (NSString *command in session.written) {
            if (targets(command, verbs)) {
                targeted++;
                allTarget7 = allTarget7 && [command rangeOfString:@"$7"].location != NSNotFound;
            }
            nameAbsent = nameAbsent && [command rangeOfString:name].location == NSNotFound;
            noInjection = noInjection && [command rangeOfString:@"run-shell"].location == NSNotFound &&
                          [command rangeOfString:@"kill-server"].location == NSNotFound;
        }
        printf("  session name %s: %lu targeted commands\n", name.UTF8String, (unsigned long)targeted);
        DRIVER_EXPECT(targeted >= 7 && allTarget7, "adversarial session names: every command targets $7");
        DRIVER_EXPECT(nameAbsent, "adversarial session names: no command contains the name");
        DRIVER_EXPECT(noInjection, "adversarial session names: no command contains run-shell or kill-server");
    }

    FakeTmuxSession *session = [[[FakeTmuxSession alloc] init] autorelease];
    TmuxController *controller = controllerFor(session);
    [controller sessionChangedTo:@"s" sessionId:7];
    [session.written removeAllObjects];
    [controller renameWindowWithId:3 inSessionNumber:@7 toName:@"w\" ; run-shell \"x"];
    DRIVER_EXPECT([session.written.lastObject isEqualToString:@"rename-window -t \"$7:@3\" \"w\\\" ; run-shell \\\"x\"\r"],
                  "a window name stays one quoted argument");

    NSSet *threeFour = [NSSet setWithObjects:@3, @4, nil];
    [controller getHiddenWindowsResponse:@"3,4"];
    DRIVER_EXPECT([[controller valueForKey:@"hiddenWindows_"] isEqual:threeFour], "legacy option values are read: @hidden");
    [controller getHiddenWindowsResponse:[@"i_" stringByAppendingString:hex(@"3,4")]];
    DRIVER_EXPECT([[controller valueForKey:@"hiddenWindows_"] isEqual:threeFour], "encoded option values are read: @hidden");
    [controller getHiddenWindowsResponse:@"i_zz1"];
    DRIVER_EXPECT([[controller valueForKey:@"hiddenWindows_"] count] == 0, "a malformed encoded value reads as empty");

    [controller getHiddenWindowsResponse:@"3,4"];
    [session.written removeAllObjects];
    [controller saveHiddenWindows];
    NSString *saved = session.written.lastObject;
    NSString *prefix = @"set -t $7 @hidden \"i_";
    NSString *value = [saved hasPrefix:prefix] && [saved hasSuffix:@"\"\r"]
        ? [saved substringWithRange:NSMakeRange(prefix.length, saved.length - prefix.length - 2)] : nil;
    DRIVER_EXPECT(value.length > 0 &&
                  [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location == NSNotFound &&
                  ([value isEqualToString:hex(@"3,4")] || [value isEqualToString:hex(@"4,3")]),
                  "saved options are hex: @hidden");

    [controller getOriginsResponse:@"1,2:10,20"];
    NSDictionary *plainOrigins = [[[controller valueForKey:@"origins_"] copy] autorelease];
    [controller getOriginsResponse:[@"o_" stringByAppendingString:hex(@"1,2:10,20")]];
    DRIVER_EXPECT(plainOrigins.count == 2 && [[controller valueForKey:@"origins_"] isEqual:plainOrigins],
                  "legacy option values are read: @origins, as the encoded form is");

    [controller getAffinitiesResponse:@"1,2;"];
    NSSet *plainAffinities = [NSSet setWithArray:[[controller valueForKey:@"affinities_"] classes]];
    [controller getAffinitiesResponse:[@"a_" stringByAppendingString:hex(@"1,2;")]];
    NSSet *encodedAffinities = [NSSet setWithArray:[[controller valueForKey:@"affinities_"] classes]];
    DRIVER_EXPECT(plainAffinities.count > 0 && [encodedAffinities isEqual:plainAffinities] &&
                  [[[controller valueForKey:@"affinities_"] valuesEqualTo:@"1"] containsObject:@"2"],
                  "legacy option values are read: @affinities, as the encoded form is");

    // A stored value is read back, then the app saves its own: a hostile plain value from the server must
    // never reach the written command, which carries only the a_/o_ prefix and lowercase hex. With no
    // windows open the saved payload is empty, so the exact commands pin the encoding.
    NSString *hostile = @"1\"; run-shell \"touch /tmp/pwned";
    [controller getAffinitiesResponse:hostile];
    [controller getOriginsResponse:hostile];
    [session.written removeAllObjects];
    [controller saveAffinities];
    [controller saveWindowOrigins];
    BOOL hostileAbsent = YES;
    for (NSString *command in session.written) {
        hostileAbsent = hostileAbsent && [command rangeOfString:@"run-shell"].location == NSNotFound;
    }
    DRIVER_EXPECT([session.written containsObject:@"set -t $7 @affinities \"a_\"\r"],
                  "saved options are hex: @affinities");
    DRIVER_EXPECT([session.written containsObject:@"set -t $7 @origins \"o_\"\r"],
                  "saved options are hex: @origins");
    DRIVER_EXPECT(hostileAbsent, "option values never escape their quotes: a stored value is not written back");
})
