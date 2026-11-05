#!/usr/bin/env python3
"""Stage NKTouch 0.7.14 Notes screen format hotfix.

v0.7.13 installed an editable, user-owned test_inputtext_notes.lua.
We must not silently overwrite edits. Ship a new test_inputtext_notes_v2.lua,
install it only when missing, and route Samples to that corrected copy.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v0714-notes-screenfix.py <staged-upstream>")
root=Path(sys.argv[1])
ui=root/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if not ui.is_file():
    raise SystemExit("missing staged Lua Workspace")
src=ui.read_text()
replacements={
    'NSString *sampleName=@"test_inputtext_notes.lua";':
        'NSString *sampleName=@"test_inputtext_notes_v2.lua";',
    'NSString *packaged=@"/var/jb/usr/share/nktouch/examples/test_inputtext_notes.lua";':
        'NSString *packaged=@"/var/jb/usr/share/nktouch/examples/test_inputtext_notes_v2.lua";',
    'initWithScriptName:@"test_inputtext_notes.lua"':
        'initWithScriptName:@"test_inputtext_notes_v2.lua"',
}
for before,after in replacements.items():
    assert src.count(before)==1, f"unexpected v0.7.13 baseline: {before}"
    src=src.replace(before,after,1)
assert 'test_inputtext_notes_v2.lua' in src
assert 'NKSaveTarget(sampleName,@"com.apple.mobilenotes",@"Ghi chú")' in src
ui.write_text(src)
print("NKTouch 0.7.14: install v2 Notes sample and route Samples without overwriting v1")
