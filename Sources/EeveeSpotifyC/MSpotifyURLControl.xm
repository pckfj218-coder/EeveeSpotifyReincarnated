#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static __weak id MSpotifyPlaybackController = nil;

static BOOL MSpotifySend(id controller, NSString *command) {
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

static UIControl *MSpotifyFindControl(UIView *view, NSString *identifier) {
    if ([view isKindOfClass:UIControl.class] && [view.accessibilityIdentifier isEqualToString:identifier]) return (UIControl *)view;
    for (UIView *child in view.subviews) {
        UIControl *found = MSpotifyFindControl(child, identifier);
        if (found) return found;
    }
    return nil;
}

static BOOL MSpotifyFallback(NSString *command) {
    NSString *identifier = nil;
    if ([command isEqualToString:@"play"] || [command isEqualToString:@"pause"] || [command isEqualToString:@"toggle"]) identifier = @"SPTNowPlayingPlayButton";
    else if ([command isEqualToString:@"next"]) identifier = @"SPTNowPlayingNextTrackButton";
    else if ([command isEqualToString:@"previous"]) identifier = @"SPTNowPlayingPreviousTrackButton";
    if (!identifier) return NO;
    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        UIControl *control = MSpotifyFindControl(window, identifier);
        if (!control) continue;
        NSString *label = control.accessibilityLabel.lowercaseString ?: @"";
        if ([command isEqualToString:@"play"] && [label containsString:@"pause"]) return YES;
        if ([command isEqualToString:@"pause"] && [label containsString:@"play"]) return YES;
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    return NO;
}

static BOOL MSpotifyHandleURL(NSURL *url) {
    if (!url || ![url.scheme.lowercaseString isEqualToString:@"mspotify"]) return NO;
    NSString *command = url.host.lowercaseString;
    if (command.length == 0) command = [url.path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]].lowercaseString;
    if (![@[@"play", @"pause", @"toggle", @"next", @"previous"] containsObject:command]) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!MSpotifySend(MSpotifyPlaybackController, command)) MSpotifyFallback(command);
    });
    return YES;
}

%hook SPTNowPlayingPlaybackControllerImplementation
- (id)initWithPlayer:(id)player testManager:(id)testManager inStreamClient:(id)inStreamClient {
    id result = %orig;
    MSpotifyPlaybackController = result;
    return result;
}
%end

%hook SpotifyAppDelegate
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary *)options {
    return MSpotifyHandleURL(url) ? YES : %orig;
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)source annotation:(id)annotation {
    return MSpotifyHandleURL(url) ? YES : %orig;
}
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    return MSpotifyHandleURL(url) ? YES : %orig;
}
%end