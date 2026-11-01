// NKTouch v0.2 compact status overlay
// SPDX-License-Identifier: GPL-3.0-or-later

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static NSString * const NKStatusPath = @"/var/mobile/Library/NKTouch/status.state";

@interface NKStatusOverlayController : NSObject
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIView *container;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UIView *track;
@property(nonatomic,strong) UIView *progress;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) NSString *lastPayload;
@property(nonatomic,assign) CFTimeInterval lastChange;
@property(nonatomic,assign) NSTimeInterval autoHideAfter;
@end

@implementation NKStatusOverlayController

+ (instancetype)shared {
    static NKStatusOverlayController *obj;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ obj = [NKStatusOverlayController new]; });
    return obj;
}

- (UIWindowScene *)activeScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
                return (UIWindowScene *)scene;
            }
        }
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) return (UIWindowScene *)scene;
        }
    }
    return nil;
}

- (void)buildWindowIfNeeded {
    if (self.window) return;

    CGRect bounds = UIScreen.mainScreen.bounds;
    UIWindowScene *scene = [self activeScene];
    if (@available(iOS 13.0, *)) {
        if (scene) self.window = [[UIWindow alloc] initWithWindowScene:scene];
    }
    if (!self.window) self.window = [[UIWindow alloc] initWithFrame:bounds];

    self.window.frame = bounds;
    self.window.windowLevel = UIWindowLevelStatusBar + 60.0;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.userInteractionEnabled = NO;
    self.window.hidden = NO;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    vc.view.userInteractionEnabled = NO;
    self.window.rootViewController = vc;

    self.container = [[UIView alloc] initWithFrame:CGRectZero];
    self.container.userInteractionEnabled = NO;
    self.container.layer.masksToBounds = YES;
    self.container.hidden = YES;
    [vc.view addSubview:self.container];

    self.label = [[UILabel alloc] initWithFrame:CGRectZero];
    self.label.textColor = UIColor.whiteColor;
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightSemibold];
    self.label.adjustsFontSizeToFitWidth = YES;
    self.label.minimumScaleFactor = 0.68;
    [self.container addSubview:self.label];

    self.track = [[UIView alloc] initWithFrame:CGRectZero];
    self.track.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
    [self.container addSubview:self.track];

    self.progress = [[UIView alloc] initWithFrame:CGRectZero];
    [self.container addSubview:self.progress];

    [self layoutOverlay];
}

- (void)layoutOverlay {
    if (!self.container) return;
    CGRect bounds = UIScreen.mainScreen.bounds;
    CGFloat screenW = CGRectGetWidth(bounds);
    CGFloat width = 74.0;
    CGFloat height = 19.0;
    CGFloat x = screenW * 0.275;
    CGFloat y = 4.0;

    self.window.frame = bounds;
    self.container.frame = CGRectMake(x, y, width, height);
    self.container.layer.cornerRadius = height / 2.0;

    self.label.frame = CGRectMake(5.0, 1.5, width - 10.0, 12.5);

    CGFloat barX = 7.0;
    CGFloat barY = height - 4.0;
    CGFloat barW = width - 14.0;
    CGFloat barH = 1.5;
    self.track.frame = CGRectMake(barX, barY, barW, barH);
    self.track.layer.cornerRadius = barH / 2.0;
    self.progress.layer.cornerRadius = barH / 2.0;
}

- (NSString *)compactMessage:(NSString *)message {
    NSString *m = [message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([m hasPrefix:@"Đang nhập "]) m = [m substringFromIndex:@"Đang nhập ".length];
    else if ([m isEqualToString:@"Đang lấy dữ liệu"]) m = @"Dữ liệu";
    else if ([m isEqualToString:@"Hoàn tất"]) m = @"Xong";
    else if ([m isEqualToString:@"Khởi động"]) m = @"Khởi";
    return m;
}

- (void)applyStyle:(NSString *)style {
    UIColor *accent = UIColor.systemCyanColor;
    UIColor *bg = [UIColor colorWithWhite:0.0 alpha:0.30];
    self.autoHideAfter = 15.0;

    if ([style isEqualToString:@"success"]) {
        accent = UIColor.systemGreenColor;
        bg = [UIColor colorWithRed:0.05 green:0.25 blue:0.10 alpha:0.82];
        self.autoHideAfter = 2.5;
    } else if ([style isEqualToString:@"error"]) {
        accent = UIColor.systemRedColor;
        bg = [UIColor colorWithRed:0.35 green:0.04 blue:0.04 alpha:0.86];
        self.autoHideAfter = 4.0;
    } else if ([style isEqualToString:@"warning"]) {
        accent = UIColor.systemOrangeColor;
        bg = [UIColor colorWithRed:0.35 green:0.20 blue:0.02 alpha:0.86];
        self.autoHideAfter = 4.0;
    }

    self.container.backgroundColor = bg;
    self.progress.backgroundColor = accent;
}

- (void)renderPayload:(NSString *)payload {
    NSArray<NSString *> *parts = [payload componentsSeparatedByString:@"|"];
    if (parts.count < 2) return;

    NSString *style = parts[0].lowercaseString;
    if ([style isEqualToString:@"hide"]) {
        self.container.hidden = YES;
        return;
    }

    NSInteger pct = [parts[1] integerValue];
    pct = MAX(0, MIN(100, pct));
    NSString *message = parts.count >= 3 ? parts[2] : @"";
    message = [self compactMessage:message];

    [self applyStyle:style];
    [self layoutOverlay];

    NSString *prefix = @"";
    if ([style isEqualToString:@"success"]) prefix = @"✓ ";
    else if ([style isEqualToString:@"error"]) prefix = @"! ";
    else if ([style isEqualToString:@"warning"]) prefix = @"⚠ ";

    if (message.length > 0) {
        if ([style isEqualToString:@"normal"]) self.label.text = [NSString stringWithFormat:@"%ld%% %@", (long)pct, message];
        else self.label.text = [prefix stringByAppendingString:message];
    } else {
        self.label.text = [style isEqualToString:@"normal"] ? [NSString stringWithFormat:@"%ld%%", (long)pct] : prefix;
    }

    CGFloat barX = 7.0;
    CGFloat barY = CGRectGetHeight(self.container.bounds) - 4.0;
    CGFloat barW = CGRectGetWidth(self.container.bounds) - 14.0;
    CGFloat barH = 1.5;
    CGFloat fraction = ((CGFloat)pct) / 100.0;
    if (![style isEqualToString:@"normal"] && pct == 0) fraction = 1.0;
    self.progress.frame = CGRectMake(barX, barY, barW * fraction, barH);

    self.container.hidden = NO;
    self.lastChange = CACurrentMediaTime();
}

- (void)poll {
    [self buildWindowIfNeeded];
    NSString *payload = [NSString stringWithContentsOfFile:NKStatusPath encoding:NSUTF8StringEncoding error:nil];
    payload = [payload stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    if (payload.length > 0 && ![payload isEqualToString:self.lastPayload]) {
        self.lastPayload = payload;
        [self renderPayload:payload];
    }

    if (!self.container.hidden && self.autoHideAfter > 0 && self.lastChange > 0) {
        if (CACurrentMediaTime() - self.lastChange > self.autoHideAfter) self.container.hidden = YES;
    }
}

- (void)start {
    NSString *base = [NKStatusPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:nil];
    [self buildWindowIfNeeded];
    if (!self.timer) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(poll) userInfo:nil repeats:YES];
    }
    [self poll];
}

@end

extern "C" void NKStatusOverlayStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NKStatusOverlayController shared] start];
    });
}
