// spec: candidates/README.md "3.2.9" -- 10.9 has no Metal: a session never allows it, saying there is no
//       GPU, so the legacy renderer always draws, and nothing loads Metal.framework or MetalKit.framework.
#import <mach-o/dyld.h>
#include <string.h>
#import "driver.h"
#import "PTYSession.h"

DRIVER_MAIN({
    PTYSession *session = [[[PTYSession alloc] initSynthetic:NO] autorelease];
    iTermMetalUnavailableReason reason = iTermMetalUnavailableReasonNone;
    DRIVER_EXPECT(![session metalAllowed:&reason], "metal: a session does not allow Metal");
    DRIVER_EXPECT(reason == iTermMetalUnavailableReasonNoGPU, "metal: the reason is that there is no GPU");
    BOOL loaded = NO;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *image = _dyld_get_image_name(i);
        if (strstr(image, "/Metal.framework/") || strstr(image, "/MetalKit.framework/")) {
            printf("loaded: %s\n", image);
            loaded = YES;
        }
    }
    DRIVER_EXPECT(!loaded, "metal: neither Metal.framework nor MetalKit.framework is loaded");
});
