#!/usr/bin/env python3
"""Patch NKTouch v0.7.14 staged Lua Workspace with a built-in test library.

- Install examples on first launch; never replace user-edited Lua files.
- Provide a four-item Samples menu (Core, Vision, InputText, Gestures).
- Core/Vision samples use Safari as a safe read-only foreground target.
- Gestures remain disabled and have no auto-assigned app target.
"""
from pathlib import Path
import sys

if len(sys.argv)!=2:
    raise SystemExit("usage: apply-v0715-selftest-suite.py <staged-upstream>")
root=Path(sys.argv[1])
ui=root/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if not ui.is_file():
    raise SystemExit("staged Lua Workspace missing")
src=ui.read_text()
first=src.index("#pragma mark - Library\n")
last=src.index("#pragma mark - Editor\n",first)
library=src[first:last]

installer=r'''
    // NKTouch 0.7.15 built-in Lua function tests. Do not overwrite any
    // existing scripts (they belong to the user).
    NSArray<NSDictionary *> *builtInTests=@[
        @{@"file":@"test_core_readonly.lua", @"bundle":@"com.apple.mobilesafari"},
        @{@"file":@"test_vision_oneframe.lua", @"bundle":@"com.apple.mobilesafari"},
        @{@"file":@"test_gestures_optin.lua"}
    ];
    for (NSDictionary *test in builtInTests) {
        NSString *testName=test[@"file"];
        NSString *testPath=NKPath(testName);
        if (![sampleFS fileExistsAtPath:testPath]) {
            NSString *source=[@"/var/jb/usr/share/nktouch/examples" stringByAppendingPathComponent:testName];
            NSError *copyError=nil;
            if ([sampleFS copyItemAtPath:source toPath:testPath error:&copyError]) {
                NSString *bundle=test[@"bundle"];
                if (bundle.length && !NKTargetForScript(testName))
                    NKSaveTarget(testName,bundle,@"Safari");
            } else NSLog(@"NKTouch self-test installation skipped %@ %@",testName,copyError);
        }
    }
'''
anchor='    if (![sampleFS fileExistsAtPath:samplePath]) {'
assert library.count(anchor)==1,"v0.7.14 Notes sample install missing"
library=library.replace(anchor,installer+anchor,1)

# V0.7.14 Samples row has one early return to the Notes sample.
old='if(ip.row==self.scripts.count+1){[self.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:@"test_inputtext_notes_v2.lua"] animated:YES];return;}'
new='if(ip.row==self.scripts.count+1){[self nkShowSamples];return;}'
assert library.count(old)==1,"unexpected v0.7.14 Samples handler"
library=library.replace(old,new,1)

# One menu rather than many loose buttons on an already dense mobile editor.
method=r'''
- (void)nkShowSamples {
    if (self.presentedViewController) return;
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"Lua Function Self-Test"
        message:@"Chọn bài kiểm tra. Core và Vision chỉ đọc; thao tác chạm phải bật thủ công."
        preferredStyle:UIAlertControllerStyleAlert];
    NSArray<NSDictionary *> *items=@[
        @{@"title":@"Core • màu / ảnh / hệ thống", @"file":@"test_core_readonly.lua"},
        @{@"title":@"Vision • 1 ảnh, nhiều phép tìm", @"file":@"test_vision_oneframe.lua"},
        @{@"title":@"InputText • thử trên Ghi chú", @"file":@"test_inputtext_notes_v2.lua"},
        @{@"title":@"Tap / Hold / Swipe • tuỳ chọn", @"file":@"test_gestures_optin.lua"}
    ];
    __weak typeof(self) weakSelf=self;
    for (NSDictionary *item in items) {
        NSString *label=item[@"title"];
        [menu addAction:[UIAlertAction actionWithTitle:label
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            __strong typeof(weakSelf) owner=weakSelf;
            if (!owner) return;
            NSString *script=item[@"file"];
            if (![[NSFileManager defaultManager] fileExistsAtPath:NKPath(script)]) {
                UIAlertController *err=[UIAlertController alertControllerWithTitle:@"Thiếu script mẫu"
                    message:@"Không tìm thấy file thử nghiệm. Kiểm tra gói NKTouch."
                    preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
                [owner presentViewController:err animated:YES completion:nil];
                return;
            }
            [owner.navigationController pushViewController:
                [[NKLuaEditorViewController alloc]initWithScriptName:script] animated:YES];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
'''
needle='- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{'
assert library.count(needle)==1,"Lua Library didSelect missing"
library=library.replace(needle,method+needle,1)
assert 'test_gestures_optin.lua' in library and 'nkShowSamples' in library
assert 'test_inputtext_notes_v2.lua' in library
src=src[:first]+library+src[last:]
ui.write_text(src)
print("NKTouch 0.7.15: Core/Vision/Input/Gesture Samples installed without overwrites")
