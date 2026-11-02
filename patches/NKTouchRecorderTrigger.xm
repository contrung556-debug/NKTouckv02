// NKTouch Recorder V5 hardware trigger
//
// AutoTouch-style control: while Recorder is recording or paused, hold
// Volume Down for 0.5s to request a clean stop from anywhere. The trigger
// itself performs no recorder/file work in SpringBoard; it only posts a
// Darwin notification. The existing mobile zxtouch-runner daemon does the
// actual finish/render work.
//
// The guarded long-press state-machine pattern is adapted from the GPLv3
// Triggr 1.x project by Jond-ie, simplified to one Recorder-only trigger.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>

static const CFTimeInterval NKRecorderHoldDelay = 0.5;
static const char *NKRecorderVolumeHoldNotification = "com.nk.nktouch.recorder.volume-down-hold";
static NSString * const NKRecorderModePath = @"/var/mobile/Library/NKTouch/recorder-v3/mode";

static BOOL nkVolumeDownHeld = NO;
static BOOL nkHoldFired = NO;
static NSUInteger nkHoldGeneration = 0;

static BOOL NKRecorderHardwareControlActive(void) {
    NSString *mode = [[NSString stringWithContentsOfFile:NKRecorderModePath
                                                encoding:NSUTF8StringEncoding
                                                   error:nil]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [mode isEqualToString:@"recording"] || [mode isEqualToString:@"paused"];
}

%hook SBVolumeHardwareButton

- (void)volumeDecreasePress:(UIGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        if (NKRecorderHardwareControlActive()) {
            nkVolumeDownHeld = YES;
            nkHoldFired = NO;
            NSUInteger generation = ++nkHoldGeneration;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NKRecorderHoldDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!nkVolumeDownHeld || nkHoldFired || generation != nkHoldGeneration) return;
                if (!NKRecorderHardwareControlActive()) return;
                nkHoldFired = YES;
                notify_post(NKRecorderVolumeHoldNotification);
            });
        }
        // Keep the system's own volume handling balanced. The Recorder hold is
        // an additional action; short Volume Down presses remain completely normal.
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
