#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL MSpotifyHandleURL(NSURL *url) {
    if (!url || ![[url.scheme lowercaseString] isEqualToString:@"mspotify"]) return NO;

    NSString *command = url.host.length ? url.host.lowercaseString : nil;
    if (command.length == 0) {
        NSString *path = [url.path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
        command = path.lowercaseString;
    }
    NSSet *allowed = [NSSet setWithArray:@[@"play", @"pause", @"toggle", @"next", @"previous"]];
    if (![allowed containsObject:command]) return NO;

    Class bridge = NSClassFromString(@"MSpotifyCommandBridge");
    SEL selector = NSSelectorFromString(@"execute:");
    if (!bridge || ![bridge respondsToSelector:selector]) return NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(bridge, selector, command);
    });
    return YES;
}

%hookf(BOOL, UIApplicationMain, int argc, char * _Nullable *argv, NSString *principalClassName, NSString *delegateClassName) {
    Class delegateClass = delegateClassName.length ? NSClassFromString(delegateClassName) : nil;
    if (delegateClass) {
        SEL modern = @selector(application:openURL:options:);
        Method modernMethod = class_getInstanceMethod(delegateClass, modern);
        IMP originalModern = modernMethod ? method_getImplementation(modernMethod) : NULL;
        id modernBlock = ^BOOL(id self, UIApplication *application, NSURL *url, NSDictionary *options) {
            if (MSpotifyHandleURL(url)) return YES;
            return originalModern ? ((BOOL (*)(id, SEL, UIApplication *, NSURL *, NSDictionary *))originalModern)(self, modern, application, url, options) : NO;
        };
        class_replaceMethod(delegateClass, modern, imp_implementationWithBlock(modernBlock), "B@:@@@");

        SEL legacy = @selector(application:openURL:sourceApplication:annotation:);
        Method legacyMethod = class_getInstanceMethod(delegateClass, legacy);
        IMP originalLegacy = legacyMethod ? method_getImplementation(legacyMethod) : NULL;
        id legacyBlock = ^BOOL(id self, UIApplication *application, NSURL *url, NSString *source, id annotation) {
            if (MSpotifyHandleURL(url)) return YES;
            return originalLegacy ? ((BOOL (*)(id, SEL, UIApplication *, NSURL *, NSString *, id))originalLegacy)(self, legacy, application, url, source, annotation) : NO;
        };
        class_replaceMethod(delegateClass, legacy, imp_implementationWithBlock(legacyBlock), "B@:@@@@");
    }
    return %orig(argc, argv, principalClassName, delegateClassName);
}