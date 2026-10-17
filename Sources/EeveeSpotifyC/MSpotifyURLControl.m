#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static __weak id MSPlaybackController;
static IMP MSOriginalSetDelegate;
static IMP MSOriginalSceneSetDelegate;
static IMP MSOriginalModernOpen;
static IMP MSOriginalLegacyOpen;
static IMP MSOriginalSceneOpen;

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

static void MSShowTestAlert(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = nil;
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (window.isKeyWindow) {
                controller = window.rootViewController;
                break;
            }
        }
        if (!controller) {
            controller = UIApplication.sharedApplication.windows.firstObject.rootViewController;
        }
        while (controller.presentedViewController) {
            controller = controller.presentedViewController;
        }
        if (!controller) return;

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"MSpotifyURLControl OK"
                                                message:@"mspotify URL received"
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}
static BOOL MSHandleURL(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    NSString *command = nil;

    if ([scheme isEqualToString:@"mspotify"]) {
        command = url.host.lowercaseString;
    } else if ([scheme isEqualToString:@"spotify"] &&
               [url.host.lowercaseString isEqualToString:@"mspotify"]) {
        command = url.path.lowercaseString;
        while ([command hasPrefix:@"/"]) {
            command = [command substringFromIndex:1];
        }
    } else {
        return NO;
    }

    if ([command isEqualToString:@"test"]) {
        MSShowTestAlert();
        return YES;
    }
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

static void MSSceneOpen(id self, SEL _cmd, UIScene *scene, NSSet *contexts) {
    for (id context in contexts) {
        NSURL *url = nil;
        if ([context respondsToSelector:@selector(URL)]) {
            url = ((id (*)(id, SEL))objc_msgSend)(context, @selector(URL));
        }
        if (url && MSHandleURL(url)) return;
    }
    if (MSOriginalSceneOpen) {
        ((void (*)(id, SEL, UIScene *, NSSet *))MSOriginalSceneOpen)(self, _cmd, scene, contexts);
    }
}

static void MSInstallSceneDelegateHooks(id delegate) {
    Class cls = object_getClass(delegate);
    SEL selector = NSSelectorFromString(@"scene:openURLContexts:");
    Method method = class_getInstanceMethod(cls, selector);
    if (method && method_getImplementation(method) != (IMP)MSSceneOpen) {
        MSOriginalSceneOpen = method_getImplementation(method);
        method_setImplementation(method, (IMP)MSSceneOpen);
    }
}

static void MSSceneSetDelegate(id self, SEL _cmd, id delegate) {
    ((void (*)(id, SEL, id))MSOriginalSceneSetDelegate)(self, _cmd, delegate);
    if (delegate) MSInstallSceneDelegateHooks(delegate);
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

        if (@available(iOS 13.0, *)) {
            Method sceneSetDelegate = class_getInstanceMethod(UIScene.class, @selector(setDelegate:));
            if (sceneSetDelegate) {
                MSOriginalSceneSetDelegate = method_getImplementation(sceneSetDelegate);
                if (MSOriginalSceneSetDelegate != (IMP)MSSceneSetDelegate) {
                    method_setImplementation(sceneSetDelegate, (IMP)MSSceneSetDelegate);
                }
            }
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (scene.delegate) MSInstallSceneDelegateHooks(scene.delegate);
            }
        }

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
