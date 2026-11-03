#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: apply-v0756-control-foundation.py <upstream-dir>')

root = Path(sys.argv[1])
repo = Path(__file__).resolve().parents[1]
runner = root / 'zxtouch-runner/main.m'
settings = root / 'zxtouch/zxtouch/Settings/SettingsPageViewController.m'
trigger = root / 'nktouch-trigger/Tweak.xm'
template = repo / 'patches/NKTouchHotkeyEngine.xm'
for p in (runner, settings, trigger, template):
    if not p.exists():
        raise SystemExit(f'missing required file: {p}')

# 1) Replace V5's one-purpose trigger with the v0.7.5.6 hotkey/feedback
# foundation. The actual recorder finish remains in the mobile runner.
trigger.write_text(template.read_text())

# 2) Add accepted + success/failure completion channels. Darwin notifications
# carry no secret data and SpringBoard never reads recorder files.
r = runner.read_text()
completed = 'static const char *kNKRecorderCompletedNotification = "com.nk.nktouch.recorder.completed";\n'
extra = completed + '''static const char *kNKRecorderAcceptedNotification = "com.nk.nktouch.recorder.accepted";\nstatic const char *kNKRecorderCompletedOKNotification = "com.nk.nktouch.recorder.completed.ok";\nstatic const char *kNKRecorderCompletedFailedNotification = "com.nk.nktouch.recorder.completed.failed";\n'''
if 'kNKRecorderAcceptedNotification' not in r:
    if completed not in r:
        raise SystemExit('V5 completion notification marker missing')
    r = r.replace(completed, extra, 1)

mode_guard = '        if (!NKRecorderModeIsActive()) return;\n\n'
accepted_guard = '        if (!NKRecorderModeIsActive()) return;\n        notify_post(kNKRecorderAcceptedNotification);\n\n'
if 'notify_post(kNKRecorderAcceptedNotification);' not in r:
    if mode_guard not in r:
        raise SystemExit('V5 recorder active guard missing')
    r = r.replace(mode_guard, accepted_guard, 1)

old_complete = '    notify_post(kNKRecorderCompletedNotification);\n'
new_complete = '''    notify_post(kNKRecorderCompletedNotification);\n    notify_post(code == 0 ? kNKRecorderCompletedOKNotification : kNKRecorderCompletedFailedNotification);\n'''
if 'kNKRecorderCompletedOKNotification : kNKRecorderCompletedFailedNotification' not in r:
    if old_complete not in r:
        raise SystemExit('V5 completion post marker missing')
    r = r.replace(old_complete, new_complete, 1)
runner.write_text(r)

# 3) Keep Recorder V5 semantics but expose the package/control-foundation version
# in the UI and explain that a hardware finish now acknowledges outside the app.
s = settings.read_text()
s = s.replace('NKTouch 0.7.5.5', 'NKTouch 0.7.5.6')
s = s.replace('nkLabel:@"0.7.5.5"', 'nkLabel:@"0.7.5.6"')
s = s.replace('text:@"0.7.5.5"', 'text:@"0.7.5.6"')
s = s.replace('self.detailLabel.text=@"Giữ Volume ↓ 0.5s = Stop + Lua";',
              'self.detailLabel.text=@"Giữ Volume ↓ 0.5s = Stop + Lua • rung xác nhận";', 1)
settings.write_text(s)

print('Applied NKTouch 0.7.5.6 Control Foundation')
