#import "SpaceBridge.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>

static void *skyLight(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW);
    });
    return handle;
}

bool SLCanMoveWindows(void) {
    if (!skyLight()) return false;
    Class operation = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
    return operation &&
        [operation instancesRespondToSelector:NSSelectorFromString(@"initWithWindows:spaceID:")] &&
        [operation instancesRespondToSelector:NSSelectorFromString(@"performWithWMBridgeDelegate")];
}

bool SLMoveWindowToSpace(uint32_t windowID, uint64_t spaceID) {
    if (!SLCanMoveWindows() || !windowID || !spaceID) return false;
    Class cls = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
    SEL init = NSSelectorFromString(@"initWithWindows:spaceID:");
    id operation = ((id (*)(id, SEL, id, uint64_t))objc_msgSend)([cls alloc], init, @[@(windowID)], spaceID);
    if (!operation) return false;
    ((void (*)(id, SEL))objc_msgSend)(operation, NSSelectorFromString(@"performWithWMBridgeDelegate"));
    return true;
}

uint64_t SLSpaceForWindow(uint32_t windowID) {
    void *handle = skyLight();
    if (!handle || !windowID) return 0;
    int32_t (*connection)(void) = dlsym(handle, "SLSMainConnectionID");
    CFArrayRef (*copy)(int32_t, int32_t, CFArrayRef) = dlsym(handle, "SLSCopySpacesForWindows");
    if (!connection || !copy) return 0;
    CFArrayRef spaces = copy(connection(), 0x7, (__bridge CFArrayRef)@[@(windowID)]);
    if (!spaces) return 0;
    uint64_t result = 0;
    if (CFArrayGetCount(spaces) > 0) {
        id value = (__bridge id)CFArrayGetValueAtIndex(spaces, 0);
        if ([value isKindOfClass:[NSNumber class]]) result = [value unsignedLongLongValue];
    }
    CFRelease(spaces);
    return result;
}

uint32_t SLWindowIDForAXElement(AXUIElementRef element) {
    if (!element) return 0;
    AXError (*getWindow)(AXUIElementRef, uint32_t *) = dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
    uint32_t result = 0;
    if (getWindow && getWindow(element, &result) != kAXErrorSuccess) result = 0;
    return result;
}
