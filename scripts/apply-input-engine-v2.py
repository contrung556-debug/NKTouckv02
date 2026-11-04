#!/usr/bin/env python3
"""Apply opt-in NKTouch Input Engine v2 to the pinned upstream GPL keyboard hooks.

Legacy task IDs 1..7, their framing, and old receiver behavior are untouched.
Task IDs 8/9 are single UTF-8 base64 packets with per-command deduplication.
The synchronous socket response acknowledges dispatch, not insertion.
"""
from pathlib import Path
import sys

if len(sys.argv)!=2:
    raise SystemExit("usage: apply-input-engine-v2.py <staged-upstream>")
root=Path(sys.argv[1])
sender=root/"pccontrol"/"UIKeyboard.xm"
receiver=root/"appdelegate"/"UIKeyboard.xm"
if not sender.is_file() or not receiver.is_file():
    raise SystemExit("missing pinned upstream keyboard implementation")

s=sender.read_text()
if "#include <string.h>" not in s:
    s=s.replace('#include "UIKeyboard.h"', '#include "UIKeyboard.h"\n#include <string.h>',1)
marker="    // Forward to appdelegate tweak injected in the frontmost app."
assert s.count(marker)==1, "unexpected sender baseline"
sender_add=r'''    // NKTouch Input Engine v2. Base64 safely carries Unicode, CR/LF and ';;'.
    // This ACK means the async notification was posted, NOT that a focused
    // field accepted the text. Never automatically resend a text mutation.
    if (taskType == 8 || taskType == 9) {
        if (data.count != 2 || ![data[1] isKindOfClass:[NSString class]]) {
            *error = [NSError errorWithDomain:@"com.nk.nktouch.input" code:400
                  userInfo:@{NSLocalizedDescriptionKey:@"-1;;INPUT_V2_INVALID_PACKET\r\n"}];
            return nil;
        }
        NSData *bytes=[[NSData alloc] initWithBase64EncodedString:data[1] options:0];
        if (!bytes || bytes.length==0 || bytes.length>8192 ||
            memchr(bytes.bytes,0,bytes.length)!=NULL) {
            *error = [NSError errorWithDomain:@"com.nk.nktouch.input" code:400
                  userInfo:@{NSLocalizedDescriptionKey:@"-1;;INPUT_V2_INVALID_UTF8\r\n"}];
            return nil;
        }
        NSString *content=[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
        if (!content) {
            *error = [NSError errorWithDomain:@"com.nk.nktouch.input" code:400
                  userInfo:@{NSLocalizedDescriptionKey:@"-1;;INPUT_V2_INVALID_UTF8\r\n"}];
            return nil;
        }
        [[NSDistributedNotificationCenter defaultCenter]
            postNotificationName:@"com.zjx.zxtouch.keyboardcontrol" object:nil
            userInfo:@{@"task_id":@"1", @"task_content":content,
                       @"nk_input_v2":@YES,
                       @"nk_input_v2_mode":(taskType==8 ? @"direct" : @"keyboard"),
                       @"nk_input_v2_id":[[NSUUID UUID] UUIDString]}
            deliverImmediately:NO];
        return @"";
    }

'''
s=s.replace(marker,sender_add+marker)
sender.write_text(s)

r=receiver.read_text()
hook="%hook UIKeyboardImpl"
assert r.count(hook)==1,"unexpected receiver hook"
helper=r'''// Find the actual focused UIKeyInput view without relying on UIWindow's
// undocumented 'firstResponder' selector. Bound recursion for custom views.
static UIView *NKInputV2FocusedView(UIView *view, NSUInteger depth) {
    if (!view || depth>64) return nil;
    if ([view isFirstResponder] && [view conformsToProtocol:@protocol(UIKeyInput)])
        return view;
    for (UIView *child in view.subviews) {
        UIView *found=NKInputV2FocusedView(child,depth+1);
        if (found) return found;
    }
    return nil;
}

'''
r=r.replace(hook,helper+hook)
legacy="        if (taskId == INSERT_TEXT)\n"
assert r.count(legacy)==1, "unexpected receiver input handler"
branch=r'''        // Opt-in v2 direct text dispatch. Dedup on the main queue: some
        // UIKeyboardImpl instances register twice or coexist in one process.
        // Only the active foreground application's focused field can receive.
        if (taskId == INSERT_TEXT && [data[@"nk_input_v2"] boolValue]) {
            NSString *content = [data[@"task_content"] isKindOfClass:[NSString class]]
                              ? data[@"task_content"] : nil;
            NSString *requestID = [data[@"nk_input_v2_id"] isKindOfClass:[NSString class]]
                                 ? data[@"nk_input_v2_id"] : nil;
            NSString *mode = [data[@"nk_input_v2_mode"] isKindOfClass:[NSString class]]
                            ? data[@"nk_input_v2_mode"] : nil;
            if (!content || !requestID || !mode || !content.length) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                static NSMutableOrderedSet<NSString *> *seen = nil;
                if (!seen) seen=[NSMutableOrderedSet new];
                if ([seen containsObject:requestID]) return;
                [seen addObject:requestID];
                if (seen.count>128) [seen removeObjectAtIndex:0];

                UIApplication *app=[UIApplication sharedApplication];
                BOOL active=NO;
                for (UIScene *scene in app.connectedScenes)
                    if ([scene isKindOfClass:[UIWindowScene class]] &&
                        scene.activationState==UISceneActivationStateForegroundActive)
                        active=YES;
                if (!active) return;
                @try {
                    BOOL inserted=NO;
                    if ([mode isEqualToString:@"direct"]) {
                        for (UIScene *scene in app.connectedScenes) {
                            if (![scene isKindOfClass:[UIWindowScene class]] ||
                                scene.activationState!=UISceneActivationStateForegroundActive)
                                continue;
                            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                                UIView *focused=NKInputV2FocusedView(window,0);
                                if (focused && [focused respondsToSelector:@selector(insertText:)]) {
                                    [(id<UIKeyInput>)focused insertText:content];
                                    inserted=YES;
                                    break;
                                }
                            }
                            if (inserted) break;
                        }
                    } else if ([mode isEqualToString:@"keyboard"]) {
                        // Explicit fallback, never automatic duplicate typing.
                        if (self.inputDelegate && [self respondsToSelector:@selector(insertText:)]) {
                            [self insertText:content];
                            inserted=YES;
                        }
                    }
                    if (!inserted)
                        NSLog(@"NKTouch InputV2: no focused compatible input; request not confirmed");
                } @catch (NSException *exception) {
                    NSLog(@"NKTouch InputV2: insertion exception (content omitted)");
                }
            });
        }
        else if (taskId == INSERT_TEXT)
'''
r=r.replace(legacy,branch)
receiver.write_text(r)
assert sender.read_text().count("nk_input_v2_id")==1
assert receiver.read_text().count("NKInputV2FocusedView")>=2
print("NKTouch Input Engine v2 staged; legacy keyboard handlers preserved")
