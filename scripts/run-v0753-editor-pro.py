#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: run-v0753-editor-pro.py <upstream-dir>')

script = Path(__file__).with_name('apply-v0753-editor-pro.py')
source = script.read_text()

old_props_block = '''old_props = '@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,assign) BOOL dirty;'
new_props = '@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,assign) BOOL dirty;@property(nonatomic,strong) UITextView *lineNumbers;@property(nonatomic,strong) NSTimer *autosaveTimer;@property(nonatomic,assign) NSTimeInterval lastBackupAt;'
if old_props not in s:
    raise SystemExit('editor property marker missing')
s = s.replace(old_props, new_props, 1)
'''

new_props_block = '''editor_iface_start = s.find('@interface NKLuaEditorViewController ()')
editor_impl_start = s.find('@implementation NKLuaEditorViewController', editor_iface_start)
if editor_iface_start < 0 or editor_impl_start < 0:
    raise SystemExit('editor private interface missing')
iface = s[editor_iface_start:editor_impl_start]
dirty_marker = '@property(nonatomic,assign) BOOL dirty;'
if dirty_marker not in iface:
    raise SystemExit('editor dirty property marker missing')
if 'UITextView *lineNumbers' not in iface:
    iface = iface.replace(
        dirty_marker,
        dirty_marker + '@property(nonatomic,strong) UITextView *lineNumbers;@property(nonatomic,strong) NSTimer *autosaveTimer;@property(nonatomic,assign) NSTimeInterval lastBackupAt;',
        1,
    )
    s = s[:editor_iface_start] + iface + s[editor_impl_start:]
'''

old_change_block = '''old_change = '- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;self.syntax.text=@"Chưa lưu";self.syntax.textColor=NKC(0xFFB545);[self highlight];}'
new_change = '- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;self.syntax.text=@"Đang chỉnh sửa…";self.syntax.textColor=NKC(0xFFB545);[self highlight];[self updateLineNumbers];[self scheduleAutosave];}'
if old_change not in s:
    raise SystemExit('textViewDidChange marker missing')
s = s.replace(old_change, new_change, 1)
'''

new_change_block = '''old_change = '- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;[self setSyntaxText:@"Chưa kiểm tra" color:NKC(0xFFB545) icon:@"circle.dashed"];[self highlight];}'
new_change = '- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;[self setSyntaxText:@"Đang chỉnh sửa…" color:NKC(0xFFB545) icon:@"circle.dashed"];[self highlight];[self updateLineNumbers];[self scheduleAutosave];}'
if old_change not in s:
    raise SystemExit('textViewDidChange marker missing')
s = s.replace(old_change, new_change, 1)
'''

old_save_block = '''old_save = '- (BOOL)save{NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;self.syntax.text=ok?@"Đã lưu":@"Lưu lỗi";self.syntax.textColor=ok?NKGreen():NKRed();return ok;}'
new_save = '- (BOOL)save{[self backupCurrentIfNeeded];NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;self.syntax.text=ok?@"Đã lưu":@"Lưu lỗi";self.syntax.textColor=ok?NKGreen():NKRed();return ok;}'
if old_save not in s:
    raise SystemExit('save marker missing')
s = s.replace(old_save, new_save, 1)
'''

new_save_block = '''old_save = '- (BOOL)save{NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;[self setSyntaxText:(ok?@"Đã lưu • Chưa check":@"Lưu lỗi") color:(ok?NKBlue():NKRed()) icon:(ok?@"circle.dashed":@"xmark.circle.fill")];return ok;}'
new_save = '- (BOOL)save{[self backupCurrentIfNeeded];NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;[self setSyntaxText:(ok?@"Đã lưu • Chưa check":@"Lưu lỗi") color:(ok?NKBlue():NKRed()) icon:(ok?@"circle.dashed":@"xmark.circle.fill")];return ok;}'
if old_save not in s:
    raise SystemExit('save marker missing')
s = s.replace(old_save, new_save, 1)
'''

for old, new, label in (
    (old_props_block, new_props_block, 'property block'),
    (old_change_block, new_change_block, 'textViewDidChange block'),
    (old_save_block, new_save_block, 'save block'),
):
    if old not in source:
        raise SystemExit(f'Editor Pro source {label} changed unexpectedly')
    source = source.replace(old, new, 1)

sys.argv = [str(script), sys.argv[1]]
ns = {'__name__': '__main__', '__file__': str(script)}
exec(compile(source, str(script), 'exec'), ns, ns)
