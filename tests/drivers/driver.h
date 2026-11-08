// spec: BUILD.md "Build evidence" -- a driver is a check linked against the built sources: each
//       expectation prints "ok:" or "FAIL:" with its name, and the driver exits with the failure count.
#import <Foundation/Foundation.h>
#include <stdio.h>

static int driver_failures;
#define DRIVER_EXPECT(cond, name) do { \
    if (cond) { printf("ok: %s\n", (name)); } \
    else { printf("FAIL: %s\n", (name)); driver_failures++; } \
  } while (0)
#define DRIVER_MAIN(body) int main(void) { @autoreleasepool { body } return driver_failures ? 1 : 0; }
