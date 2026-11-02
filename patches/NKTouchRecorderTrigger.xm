// NKTouch Recorder V5 hardware trigger
//
// AutoTouch-style control: hold Volume Down for 0.5s to request a recorder
// stop from anywhere. SpringBoard deliberately does not read NKTouch state or
// execute recorder/file work; it only posts a Darwin notification. The mobile
// zxtouch-runner daemon decides whether Recorder is active and, if so, performs
// the clean finish/render flow.
//
// The guarded long-press state-machine pattern is adapted from the GPLv3
// Triggr 1.x project by Jond-ie, simplified to one Recorder-only trigger.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>

static const CFTimeInterval NKRecorderHoldDelay = 0.5;
static const char *NKRecorderVolumeHoldNotification = "com.nk.nktouch.recorder.volume-down-hold";

static BOOL nkVolumeDownHeld = NO;
static BOOL nkHoldFired = NO;
static NSUInteger nkHoldGeneration = 0;

%hook SBVolumeHardwareButton

- (void)volumeDecreasePress:(UIGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        nkVolumeDownHeld = YES;
        nkHoldFired = NO;
        NSUInteger generation = ++nkHoldGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NKRecorderHoldDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!nkVolumeDownHeld || nkHoldFired || generation != nkHoldGeneration) return;
            nkHoldFired = YES;
            notify_post(NKRecorderVolumeHoldNotification);
        });

        // Keep the system's own volume handling balanced. The hardware hold is
        // an additional control signal; the mobile runner ignores it unless
        // Recorder is actually recording/paused.
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
