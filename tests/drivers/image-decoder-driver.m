// spec: SMOKE.md check 5 -- iTerm2 decodes inline images in image_decoder under sandbox-exec, whose profile
//       allows running only image_decoder's literal path; the app must find it however the path it was
//       launched by is spelled. The driver always runs from a path with a symlink in it: when its own
//       path has none (a build directory under /Users, say), it reruns itself through a symlink it makes.
#import "driver.h"
#import "iTermImageDecoderDriver.h"
#include <limits.h>
#include <stdlib.h>
#include <unistd.h>

static NSString *realPath(NSString *path) {
    char resolved[PATH_MAX];
    return realpath(path.fileSystemRepresentation, resolved) ? @(resolved) : nil;
}

DRIVER_MAIN({
    NSString *here = [[NSBundle mainBundle] bundlePath];
    NSString *real = realPath(here);
    if ([real isEqualToString:here]) {
        NSString *link = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"image-decoder-driver.%d", getpid()]];
        unlink(link.fileSystemRepresentation);
        DRIVER_EXPECT(symlink(real.fileSystemRepresentation, link.fileSystemRepresentation) == 0,
                      "image decoder: a symlink to the driver's directory is made");
        NSString *me = [[[NSProcessInfo processInfo] arguments][0] lastPathComponent];
        NSTask *task = [[[NSTask alloc] init] autorelease];
        task.launchPath = [link stringByAppendingPathComponent:me];
        [task launch];
        [task waitUntilExit];
        unlink(link.fileSystemRepresentation);
        exit(driver_failures + task.terminationStatus);
    }
    printf("  running from %s\n", here.UTF8String);
    DRIVER_EXPECT(real.length > 0 && ![real isEqualToString:here],
                  "image decoder: the driver runs from a path with a symlink in it");
    // The PNG is ITERM_DRIVER_PNG in the environment where it is set (a packed driver, in the 10.9 guest),
    // else the source tree's, compiled in.
    const char *pngPath = getenv("ITERM_DRIVER_PNG");
    NSData *png = [NSData dataWithContentsOfFile:pngPath ? @(pngPath) : @ITERM_DRIVER_PNG];
    DRIVER_EXPECT(png.length > 0, "image decoder: the sample PNG reads");
    NSData *json = [[[[iTermImageDecoderDriver alloc] init] autorelease] jsonForCompressedImageData:png];
    DRIVER_EXPECT(json.length > 0, "image decoder: a PNG decodes from a path with a symlink in it");
})
