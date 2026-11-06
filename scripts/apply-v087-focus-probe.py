#!/usr/bin/env python3
"""v0.8.7 native focus probe on the pinned, already-patched v2 UIKit hooks.

READ ONLY: 24/10 query to SpringBoard, nonce-correlated distributed-notification
roundtrip to the actual foreground app, check UIWindow UIKit first responder
on its MAIN thread. No OCR, keyboard tap, clipboard access or text mutation.
The caller treats missing/timeout replies as UNKNOWN (fail closed), never YES.
"""
from pathlib import Path
import sys
if len(sys.argv)!=2:
    raise SystemExit("usage: apply-v087-focus-probe.py <staged-upstream>")
root=Path(sys.argv[1])
sender=root/"pccontrol/UIKeyboard.xm"
receiver=root/"appdelegate/UIKeyboard.xm"
if not sender.is_file() or not receiver.is_file():
    raise SystemExit("pinned v2 UIKit hooks missing")
s=sender.read_text()
r=receiver.read_text()
if "NKInputFocusProbeWaiter" in s or "NKInputV87RespondToFocusProbe" in r:
    raise SystemExit("v0.8.7 focus patch already applied")
if s.count('    // Forward to appdelegate tweak injected in the frontmost app.')!=1:
    raise SystemExit("unexpected SpringBoard sender")
if r.count('if (taskId == INSERT_TEXT && [data[@"nk_input_v2"] boolValue])')!=1:
    raise SystemExit("unexpected UIKit receiver")
if r.count('static UIView *NKInputV2FocusedView(')!=1:
    raise SystemExit("native UIKeyInput recursive view helper unavailable")

sender_helper=r'''
// NKTouch v0.8.7: correlate one read-only query with one UIKit reply.
// The socket request is on a worker thread. Never block SpringBoard main.
@interface NKInputFocusProbeWaiter : NSObject {
@public
    BOOL answered;
    BOOL focused;
    NSString *expectedID;
    NSString *expectedBundle;
    dispatch_semaphore_t event;
}
- (instancetype)initWithID:(NSString *)uuid bundle:(NSString *)bundle
                    event:(dispatch_semaphore_t)signal;
- (void)receivedFocusReply:(NSNotification *)notification;
@end
@implementation NKInputFocusProbeWaiter
- (instancetype)initWithID:(NSString *)uuid bundle:(NSString *)bundle
                    event:(dispatch_semaphore_t)signal {
    self=[super init];
    if (self) {
        expectedID=[uuid copy];
        expectedBundle=[bundle copy];
        event=signal;
    }
    return self;
}
- (void)receivedFocusReply:(NSNotification *)notification {
    NSDictionary *info=notification.userInfo;
    if (answered || ![info isKindOfClass:[NSDictionary class]]) return;
    NSString *token=info[@"nk_focus_request_id"];
    NSString *bundle=info[@"nk_focus_bundle"];
    NSNumber *ready=info[@"nk_focus_ready"];
    if (![token isKindOfClass:[NSString class]] ||
        ![bundle isKindOfClass:[NSString class]] ||
        ![ready isKindOfClass:[NSNumber class]] ||
        ![token isEqualToString:expectedID] ||
        ![bundle isEqualToString:expectedBundle]) return;
    answered=YES;
    focused=[ready boolValue];
    dispatch_semaphore_signal(event);
}
@end

'''
s=s.replace("NSString* inputTextFromRawData(UInt8 *eventData, NSError **error)\n",sender_helper+"NSString* inputTextFromRawData(UInt8 *eventData, NSError **error)\n",1)
sender_block=r'''    // Subcommand 10 is a read-only UIKeyInput focus probe.
    // A nonce reply means the foreground UIKit process checked isFirstResponder.
    // Unknown / hook unavailable / timeout MUST fail closed, never imply focus.
    if (taskType == 10) {
        NSString *bundle=(data.count==2 && [data[1] isKindOfClass:[NSString class]])
                         ? data[1] : nil;
        NSCharacterSet *valid=[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
        if (!bundle || bundle.length<3 || bundle.length>180 ||
            [bundle rangeOfCharacterFromSet:[valid invertedSet]].location!=NSNotFound) {
            *error=[NSError errorWithDomain:@"com.nk.nktouch.input.focus" code:400
                userInfo:@{NSLocalizedDescriptionKey:@"-1;;FOCUS_INVALID_BUNDLE\r\n"}];
            return nil;
        }
        if ([NSThread isMainThread]) {
            *error=[NSError errorWithDomain:@"com.nk.nktouch.input.focus" code:503
                userInfo:@{NSLocalizedDescriptionKey:@"-1;;FOCUS_UNSAFE_THREAD\r\n"}];
            return nil;
        }
        NSString *uuid=[[NSUUID UUID] UUIDString];
        dispatch_semaphore_t signal=dispatch_semaphore_create(0);
        NKInputFocusProbeWaiter *waiter=
            [[NKInputFocusProbeWaiter alloc] initWithID:uuid bundle:bundle event:signal];
        NSDistributedNotificationCenter *center=[NSDistributedNotificationCenter defaultCenter];
        dispatch_sync(dispatch_get_main_queue(), ^{
            [center addObserver:waiter selector:@selector(receivedFocusReply:)
                          name:@"com.nk.nktouch.input.focus.reply" object:nil];
        });
        [center postNotificationName:@"com.zjx.zxtouch.keyboardcontrol"
                  object:nil
                  userInfo:@{@"task_id":@"10",
                             @"nk_focus_request_id":uuid,
                             @"nk_focus_bundle":bundle}
                  deliverImmediately:NO];
        long status=dispatch_semaphore_wait(signal,
                   dispatch_time(DISPATCH_TIME_NOW,(int64_t)(700*NSEC_PER_MSEC)));
        // Return the waiter to the main queue for serialized observer removal.
        dispatch_sync(dispatch_get_main_queue(), ^{
            [center removeObserver:waiter
                              name:@"com.nk.nktouch.input.focus.reply" object:nil];
        });
        if (status!=0 || !waiter->answered) {
            *error=[NSError errorWithDomain:@"com.nk.nktouch.input.focus" code:408
                userInfo:@{NSLocalizedDescriptionKey:@"-1;;FOCUS_PROBE_TIMEOUT\r\n"}];
            return nil;
        }
        return waiter->focused ? @"1" : @"0";
    }

'''
marker="    // Forward to appdelegate tweak injected in the frontmost app."
s=s.replace(marker,sender_block+marker,1)
sender.write_text(s)

receiver_helper=r'''
// NKTouch v0.8.7: run only on the target app's UIKit main queue.
// A focused UIKit UIView must report BOTH isFirstResponder and UIKeyInput.
static void NKInputV87RespondToFocusProbe(NSString *requestID, NSString *targetBundle) {
    UIApplication *app=[UIApplication sharedApplication];
    NSString *actual=[NSBundle mainBundle].bundleIdentifier;
    if (![actual isKindOfClass:[NSString class]] ||
        ![actual isEqualToString:targetBundle]) return;
    BOOL active=NO, hasFocusedInput=NO;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]] ||
            scene.activationState!=UISceneActivationStateForegroundActive) continue;
        active=YES;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow) continue;
            UIView *focused=NKInputV2FocusedView(window,0);
            if (focused && [focused respondsToSelector:@selector(insertText:)]) {
                hasFocusedInput=YES;
                break;
            }
        }
        if (hasFocusedInput) break;
    }
    if (!active) return;
    [[NSDistributedNotificationCenter defaultCenter]
         postNotificationName:@"com.nk.nktouch.input.focus.reply" object:nil
         userInfo:@{@"nk_focus_request_id":requestID,
                    @"nk_focus_bundle":actual,
                    @"nk_focus_ready":@(hasFocusedInput)}
         deliverImmediately:NO];
}

'''
hook="%hook UIKeyboardImpl"
r=r.replace(hook,receiver_helper+hook,1)
receiver_branch=r'''        // Read-only query. Never type or move cursor in this branch.
        if (taskId == 10) {
            NSString *token=[data[@"nk_focus_request_id"] isKindOfClass:[NSString class]]
                            ? data[@"nk_focus_request_id"] : nil;
            NSString *bundle=[data[@"nk_focus_bundle"] isKindOfClass:[NSString class]]
                             ? data[@"nk_focus_bundle"] : nil;
            if (!token || token.length!=36 || !bundle || bundle.length<3) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                // Multiple UIKeyboardImpl instances may observe one notification.
                static NSMutableOrderedSet<NSString *> *seenFocus=nil;
                if (!seenFocus) seenFocus=[NSMutableOrderedSet new];
                if ([seenFocus containsObject:token]) return;
                [seenFocus addObject:token];
                if (seenFocus.count>128) [seenFocus removeObjectAtIndex:0];
                NKInputV87RespondToFocusProbe(token,bundle);
            });
        }
        else if (taskId == INSERT_TEXT && [data[@"nk_input_v2"] boolValue])'''
r=r.replace('if (taskId == INSERT_TEXT && [data[@"nk_input_v2"] boolValue])',receiver_branch,1)
receiver.write_text(r)
assert 'NKInputFocusProbeWaiter' in sender.read_text()
assert 'NKInputV87RespondToFocusProbe' in receiver.read_text()
assert 'else if (taskId == INSERT_TEXT && [data[@"nk_input_v2"] boolValue])' in receiver.read_text()
print("[NK087] staged read-only, bounded, nonce-tagged native UIKit focus probe")
