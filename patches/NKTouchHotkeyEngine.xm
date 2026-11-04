// NKTouch v0.7.5.6 Control Foundation
// SpringBoard-only hotkey detection + user feedback. Recorder work remains in
// the mobile runner; this tweak only emits/consumes Darwin notifications.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>

static const CFTimeInterval NKHotkeyHoldDelay = 0.5;
static const char *NKRecorderVolumeHoldNotification = "com.nk.nktouch.recorder.volume-down-hold";
static const char *NKRecorderAcceptedNotification = "com.nk.nktouch.recorder.accepted";
static const char *NKRecorderCompletedOKNotification = "com.nk.nktouch.recorder.completed.ok";
static const char *NKRecorderCompletedFailedNotification = "com.nk.nktouch.recorder.completed.failed";

static BOOL nkVolumeDownHeld = NO;
static BOOL nkHoldFired = NO;
static NSUInteger nkHoldGeneration = 0;
static int nkAcceptedToken = 0;
static int nkCompletedOKToken = 0;
static int nkCompletedFailedToken = 0;
static UIView *nkFeedbackView = nil;
static NSUInteger nkFeedbackGeneration = 0;

typedef NS_ENUM(NSInteger, NKHotkeyAction) {
    NKHotkeyActionNone = 0,
    NKHotkeyActionRecorderFinish = 1,
};

static UIWindow *NKFeedbackHostWindow(void) {
    UIApplication *application = UIApplication.sharedApplication;
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];

    // Prefer scene-owned windows on iOS 13+. Accessing UIApplication.windows
    // directly is deprecated and fails under Theos' -Werror flags.
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            [windows addObjectsFromArray:windowScene.windows];
        }
    }

    // SpringBoard may expose system-managed windows outside connected scenes.
    // Keep the legacy lookup as a guarded runtime fallback, not a deprecated
    // compile-time property reference.
    if (windows.count == 0) {
        id legacyWindows = [application valueForKey:@"windows"];
        if ([legacyWindows isKindOfClass:[NSArray class]]) {
            for (id candidate in (NSArray *)legacyWindows) {
                if ([candidate isKindOfClass:[UIWindow class]]) {
                    [windows addObject:(UIWindow *)candidate];
                }
            }
        }
    }

    for (UIWindow *window in [windows reverseObjectEnumerator]) {
        if (!window.hidden && window.alpha > 0.01 && window.windowLevel >= UIWindowLevelNormal) return window;
    }
    return windows.lastObject;
}

static void NKHaptic(UINotificationFeedbackType type) {
    UINotificationFeedbackGenerator *generator = [UINotificationFeedbackGenerator new];
    [generator prepare];
    [generator notificationOccurred:type];
}

static void NKShowFeedback(NSString *text, UINotificationFeedbackType type) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NKHaptic(type);
        UIWindow *window = NKFeedbackHostWindow();
        if (!window) return;

        [nkFeedbackView removeFromSuperview];
        CGFloat width = MIN(220.0, MAX(150.0, window.bounds.size.width - 40.0));
        CGFloat top = 14.0;
        if (@available(iOS 11.0, *)) top += window.safeAreaInsets.top;
        UIView *pill = [[UIView alloc] initWithFrame:CGRectMake((window.bounds.size.width-width)/2.0, top, width, 38.0)];
        pill.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        pill.layer.cornerRadius = 19.0;
        pill.layer.masksToBounds = YES;
        pill.userInteractionEnabled = NO;

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(pill.bounds, 14.0, 0.0)];
        label.text = text;
        label.textColor = UIColor.whiteColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.8;
        [pill addSubview:label];
        pill.alpha = 0.0;
        [window addSubview:pill];
        nkFeedbackView = pill;
        NSUInteger generation = ++nkFeedbackGeneration;

        [UIView animateWithDuration:0.15 animations:^{ pill.alpha = 1.0; }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != nkFeedbackGeneration || nkFeedbackView != pill) return;
            [UIView animateWithDuration:0.18 animations:^{ pill.alpha = 0.0; } completion:^(__unused BOOL finished) {
                if (nkFeedbackView == pill) nkFeedbackView = nil;
                [pill removeFromSuperview];
            }];
        });
    });
}

static void NKDispatchHotkeyAction(NKHotkeyAction action) {
    switch (action) {
        case NKHotkeyActionRecorderFinish:
            notify_post(NKRecorderVolumeHoldNotification);
            break;
        case NKHotkeyActionNone:
        default:
            break;
    }
}

static void NKRegisterControlFeedback(void) {
    dispatch_queue_t queue = dispatch_get_main_queue();
    notify_register_dispatch(NKRecorderAcceptedNotification, &nkAcceptedToken, queue, ^(__unused int token) {
        NKShowFeedback(@"REC STOPPING…", UINotificationFeedbackTypeWarning);
    });
    notify_register_dispatch(NKRecorderCompletedOKNotification, &nkCompletedOKToken, queue, ^(__unused int token) {
        NKShowFeedback(@"✓ REC SAVED", UINotificationFeedbackTypeSuccess);
    });
    notify_register_dispatch(NKRecorderCompletedFailedNotification, &nkCompletedFailedToken, queue, ^(__unused int token) {
        NKShowFeedback(@"REC ERROR", UINotificationFeedbackTypeError);
    });
}

%hook SBVolumeHardwareButton

- (void)volumeDecreasePress:(UIGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        nkVolumeDownHeld = YES;
        nkHoldFired = NO;
        NSUInteger generation = ++nkHoldGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NKHotkeyHoldDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!nkVolumeDownHeld || nkHoldFired || generation != nkHoldGeneration) return;
            nkHoldFired = YES;
            NKDispatchHotkeyAction(NKHotkeyActionRecorderFinish);
        });
        %orig;
        return;
    }

    if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled) {
        nkVolumeDownHeld = NO;
        ++nkHoldGeneration;
        %orig;
        return;
    }

    %orig;
}

%end

%ctor {
    NKRegisterControlFeedback();
}
