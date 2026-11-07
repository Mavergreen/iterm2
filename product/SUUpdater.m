// Mavericks iTerm2: a stand-in for the class named SUUpdater, so upstream's compiled MainMenu.nib binds.
//
// The 3.0.15 release's MainMenu.nib (used as is: this build has no nib compiler) instantiates an object
// of class SUUpdater and makes it the target of Check for Updates. Old Sparkle is not bundled (patch 0004; BUILD.md "Updates"); this class has none of its code or behavior. Its one method hands the click to the app
// delegate, whose checkForUpdates: launches the family updater.

#import <Cocoa/Cocoa.h>

@protocol iTermFamilyUpdaterLauncher
- (IBAction)checkForUpdates:(id)sender;
@end

@interface SUUpdater : NSObject
@end

@implementation SUUpdater

- (IBAction)checkForUpdates:(id)sender {
    [(id<iTermFamilyUpdaterLauncher>)[NSApp delegate] checkForUpdates:sender];
}

@end
