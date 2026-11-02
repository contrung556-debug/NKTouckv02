#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: apply-v07533-recorder-status-fix.py <upstream-dir>')

root = Path(sys.argv[1])
recorder = root / 'layout/usr/bin/nkrecorder'
settings = root / 'zxtouch/zxtouch/Settings/SettingsPageViewController.m'
if not recorder.exists() or not settings.exists():
    raise SystemExit('missing prepared 0.7.5.3.2 files')

r = recorder.read_text()
old = '''    last="$(latest_timeline 2>/dev/null || true)"\n    [ -n "$last" ] && echo "latest=$last"\n    ;;\n'''
new = '''    last="$(latest_timeline 2>/dev/null || true)"\n    if [ -n "$last" ]; then echo "latest=$last"; fi\n    exit 0\n    ;;\n'''
if old not in r:
    raise SystemExit('Recorder status tail marker missing')
r = r.replace(old, new, 1)
recorder.write_text(r)
recorder.chmod(0o755)

s = settings.read_text()
marker = '// V0.7.5.3.3 Recorder status fix: valid status output always returns exit 0.\n'
anchor = '// V0.7.5.3.2 Recorder spawn fix: execute nkrecorder through an available trusted shell.\n'
if marker not in s:
    s = s.replace(anchor, anchor + marker, 1) if anchor in s else marker + s
s = s.replace('NKTouch 0.7.5.3.2', 'NKTouch 0.7.5.3.3')
s = s.replace('nkLabel:@"0.7.5.3.2"', 'nkLabel:@"0.7.5.3.3"')
s = s.replace('text:@"0.7.5.3.2"', 'text:@"0.7.5.3.3"')
settings.write_text(s)

print('Applied NKTouch v0.7.5.3.3 Recorder status exit-code fix')
