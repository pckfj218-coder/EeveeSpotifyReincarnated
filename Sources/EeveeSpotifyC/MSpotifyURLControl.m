#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static __weak id MSPlaybackController;
static IMP MSOriginalSetDelegate;
static IMP MSOriginalModernOpen;
static IMP MSOriginalLegacyOpen;

static BOOL MSSendCommand(NSString *command) {
    id controller = MSPlaybackController;
    if (!controller) return NO;
    if ([command isEqualToString:@"play"] && [controller respondsToSelector:@selector(setPaused:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, @selector(setPaused:), NO); return YES;
    }
    if ([command isEqualToString:@"pause"] && [controller respondsToSelector:@selector(setPaused:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, @selector(setPaused:), YES); return YES;
    }
    if ([command isEqualToString:@"toggle"] && [controller respondsToSelector:@selector(isPaused)] && [controller respondsToSelector:@selector(setPaused:)]) {
        BOOL paused = ((BOOL (*)(id, SEL))objc_msgSend)(controller, @selector(isPaused));
        ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, @selector(setPaused:), !paused); return YES;
    }
    if ([command isEqualToString:@"next"] && [controller respondsToSelector:@selector(skipToNextWhileDragging:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, @selector(skipToNextWhileDragging:), NO); return YES;
    }
    if ([command isEqualToString:@"previous"] && [controller respondsToSelector:@selector(skipToPreviousWhileDragging:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, @selector(skipToPreviousWhileDragging:), NO); return YES;
    }
    return NO;
}

static BOOL MSHandleURL(NSURL *url) {
    if (![[url.scheme lowercaseString] isEqualToString:@"mspotify"]) return NO;
    NSString *command = url.host.lowercaseString;
    if (![@[@"play", @"pause", @"toggle", @"next", @"previous"] containsObject:command]) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{ MSSendCommand(command); });
    return YES;
}

static BOOL MSModernOpen(id self, SEL _cmd, UIApplication *app, NSURL *url, NSDictionary *options) {
    if (MSHandleURL(url)) return YES;
    return MSOriginalModernOpen ? ((BOOL (*)(id, SEL, UIApplication *, NSURL *, NSDictionary *))MSOriginalModernOpen)(self, _cmd, app, url, options) : NO;
}

static BOOL MSLegacyOpen(id self, SEL _cmd, UIApplication *app, NSURL *url, NSString *source, id annotation) {
    if (MSHandleURL(url)) return YES;
    return MSOriginalLegacyOpen ? ((BOOL (*)(id, SEL, UIApplication *, NSURL *, NSString *, id))MSOriginalLegacyOpen)(self, _cmd, app, url, source, annotation) : NO;
}

static void MSInstallDelegateHooks(id delegate) {
    Class cls = object_getClass(delegate);
    SEL modern = @selector(application:openURL:options:);
    Method modernMethod = class_getInstanceMethod(cls, modern);
    if (modernMethod && method_getImplementation(modernMethod) != (IMP)MSModernOpen) {
        MSOriginalModernOpen = method_getImplementation(modernMethod);
        method_setImplementation(modernMethod, (IMP)MSModernOpen);
    }
    SEL legacy = @selector(application:openURL:sourceApplication:annotation:);
    Method legacyMethod = class_getInstanceMethod(cls, legacy);
    if (legacyMethod && method_getImplementation(legacyMethod) != (IMP)MSLegacyOpen) {
        MSOriginalLegacyOpen = method_getImplementation(legacyMethod);
        method_setImplementation(legacyMethod, (IMP)MSLegacyOpen);
    }
}

static void MSSetDelegate(id self, SEL _cmd, id delegate) {
    ((void (*)(id, SEL, id))MSOriginalSetDelegate)(self, _cmd, delegate);
    if (delegate) MSInstallDelegateHooks(delegate);
}

static id MSPlaybackInit(id self, SEL _cmd, id player, id testManager, id streamClient) {
    id storedOriginal = objc_getAssociatedObject(object_getClass(self), _cmd);
    IMP original = NULL;
    if ([storedOriginal isKindOfClass:[NSValue class]]) {
        union { void *pointer; IMP implementation; } bits;
        bits.pointer = [(NSValue *)storedOriginal pointerValue];
        original = bits.implementation;
    }
    id result = ((id (*)(id, SEL, id, id, id))original)(self, _cmd, player, testManager, streamClient);
    MSPlaybackController = result;
    return result;
}

__attribute__((constructor)) static void MSInitialize(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Method setDelegate = class_getInstanceMethod(UIApplication.class, @selector(setDelegate:));
        MSOriginalSetDelegate = method_getImplementation(setDelegate);
        method_setImplementation(setDelegate, (IMP)MSSetDelegate);
        if (UIApplication.sharedApplication.delegate) MSInstallDelegateHooks(UIApplication.sharedApplication.delegate);

        Class playerClass = NSClassFromString(@"SPTNowPlayingPlaybackControllerImplementation");
        SEL initSelector = NSSelectorFromString(@"initWithPlayer:testManager:inStreamClient:");
        Method initMethod = class_getInstanceMethod(playerClass, initSelector);
        if (initMethod) {
            IMP original = method_getImplementation(initMethod);
            union { IMP implementation; void *pointer; } bits;
            bits.implementation = original;
            NSValue *storedOriginal = [NSValue valueWithPointer:bits.pointer];
            objc_setAssociatedObject(playerClass, initSelector, storedOriginal, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            method_setImplementation(initMethod, (IMP)MSPlaybackInit);
        }
    });
}
