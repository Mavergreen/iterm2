// spec: SECURITY.md ITERM2-URL-SCHEME -- an ssh: or telnet: link becomes a session's command, built from
//       the URL's user, host and port. A user or host that could be read as an option, or that holds
//       anything but a name's characters, refuses the whole URL, as upstream 168d0eee0f and ad73877882
//       (and its later leading-character check) do; an ordinary link still builds the usual command.
#import "driver.h"
#import "iTermController.h"
#import "ITAddressBookMgr.h"

#import "NSStringITerm.h"

NSDictionary *iTermURLSubstitutions(NSString *urlString);

@interface iTermController (DriverPrivate)
- (NSDictionary *)profile:(NSDictionary *)aDict modifiedToOpenURL:(NSString *)url forObjectType:(iTermObjectType)objectType;
@end

static NSString *commandFor(NSString *url) {
    NSDictionary *profile = @{ KEY_CUSTOM_COMMAND: @"No", KEY_COMMAND_LINE: @"" };
    NSDictionary *result = [[iTermController sharedInstance] profile:profile
                                                   modifiedToOpenURL:url
                                                       forObjectType:iTermWindowObject];
    return result ? (result[KEY_COMMAND_LINE] ?: @"(no command)") : nil;
}

DRIVER_MAIN({
    NSArray<NSString *> *refused = @[ @"ssh://-oProxyCommand=touch%20/tmp/pwned@h",
                                      @"ssh://u@-oProxyCommand=x",
                                      @"ssh://us%20er@h",
                                      @"ssh://u%3Bid@h",
                                      @"ssh://u@h%20-oProxyCommand=x",
                                      @"telnet://-x@h",
                                      @"telnet://u@-x" ];
    for (NSString *url in refused) {
        NSString *command = commandFor(url);
        printf("  %s -> %s\n", url.UTF8String, command ? command.UTF8String : "(refused)");
        DRIVER_EXPECT(command == nil, "url command: a user or host that is not a plain name refuses the URL");
    }
    DRIVER_EXPECT([commandFor(@"ssh://user.name@host.example:2222") isEqualToString:@"ssh -l user.name -p 2222 host.example"],
                  "url command: an ordinary ssh link still builds ssh -l -p host");
    DRIVER_EXPECT([commandFor(@"ssh://host-1.example") isEqualToString:@"ssh host-1.example"],
                  "url command: an ssh link without a user builds ssh host");
    DRIVER_EXPECT([commandFor(@"telnet://u_1@h.example:23") isEqualToString:@"telnet -l u_1 h.example 23"],
                  "url command: an ordinary telnet link still builds telnet -l host port");

    // A profile with a custom command gets the link's parts as $$HOST$$, $$USER$$ and the rest.
    for (NSString *url in refused) {
        DRIVER_EXPECT(iTermURLSubstitutions(url) == nil,
                      "url substitutions: a user or host that is not a plain name refuses the URL");
    }
    NSDictionary *subs = iTermURLSubstitutions(@"ssh://user.name@host.example:2222/a%20-oProxyCommand=x?q");
    DRIVER_EXPECT([subs[@"$$HOST$$"] isEqualToString:@"host.example"] && [subs[@"$$USER$$"] isEqualToString:@"user.name"] &&
                  [subs[@"$$PORT$$"] isEqualToString:@"2222"],
                  "url substitutions: an ordinary link's host, user and port are as they were");
    for (NSString *key in @[ @"$$URL$$", @"$$PATH$$", @"$$RES$$" ]) {
        NSString *command = [NSString stringWithFormat:@"ssh %@", subs[key]];
        printf("  %s -> %s\n", key.UTF8String, command.UTF8String);
        DRIVER_EXPECT([[command componentsInShellCommand] count] == 2,
                      "url substitutions: the URL, path and resource stay one argument each");
    }
    DRIVER_EXPECT(iTermURLSubstitutions(nil) != nil, "url substitutions: no URL substitutes nothing, as before");
})
