#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: run-v0753-editor-pro.py <upstream-dir>')

script = Path(__file__).with_name('apply-v0753-editor-pro.py')
source = script.read_text()

old = '''old_props = '@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,assign) BOOL dirty;'
new_props = '@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,assign) BOOL dirty;@property(nonatomic,strong) UITextView *lineNumbers;@property(nonatomic,strong) NSTimer *autosaveTimer;@property(nonatomic,assign) NSTimeInterval lastBackupAt;'
if old_props not in s:
    raise SystemExit('editor property marker missing')
s = s.replace(old_props, new_props, 1)
'''

new = '''editor_iface_start = s.find('@interface NKLuaEditorViewController ()')
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

if old not in source:
    raise SystemExit('Editor Pro source property block changed unexpectedly')
patched = source.replace(old, new, 1)

sys.argv = [str(script), sys.argv[1]]
ns = {'__name__': '__main__', '__file__': str(script)}
exec(compile(patched, str(script), 'exec'), ns, ns)
