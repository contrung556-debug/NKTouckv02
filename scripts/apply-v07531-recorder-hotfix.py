#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: apply-v07531-recorder-hotfix.py <upstream-dir>')

root = Path(sys.argv[1])
settings = root / 'zxtouch/zxtouch/Settings/SettingsPageViewController.m'
recorder = root / 'layout/usr/bin/nkrecorder'
if not settings.exists() or not recorder.exists():
    raise SystemExit('missing prepared 0.7.5.3 files')

r = recorder.read_text()
if r.startswith('#!/var/jb/bin/sh'):
    r = r.replace('#!/var/jb/bin/sh', '#!/var/jb/usr/bin/sh', 1)
r = r.replace('VERSION="0.7.5.2"', 'VERSION="0.7.5.3.1"', 1)
r = r.replace('NKTouch Recorder V3 v0.7.5.2', 'NKTouch Recorder V3 v0.7.5.3.1', 1)
recorder.write_text(r)
recorder.chmod(0o755)

s = settings.read_text()
marker = '// V0.7.5.3.1 Recorder hotfix: rootless shell path + visible runtime diagnostics.\n'
if marker not in s:
    anchor = '// V0.7.5.3 Editor Pro: line numbers, find/replace, API snippets, autosave + rolling backups.\n'
    s = s.replace(anchor, anchor + marker, 1) if anchor in s else marker + s

s = s.replace('NKTouch 0.7.5.3', 'NKTouch 0.7.5.3.1')
s = s.replace('nkLabel:@"0.7.5.3"', 'nkLabel:@"0.7.5.3.1"')
s = s.replace('text:@"0.7.5.3"', 'text:@"0.7.5.3.1"')

old = 'typeof(self)self=w;if(!self||c!=0)return;NSDictionary*d=NKParseKV(o);NSString*state=d[@"state"]?:@"idle";'
new = 'typeof(self)self=w;if(!self)return;if(c!=0){self.recState=@"error";self.stateLabel.text=@"● RECORDER LỖI";self.stateLabel.textColor=NKRed();NSString*msg=[o stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];self.detailLabel.text=msg.length?msg:@"Không chạy được nkrecorder";self.recordButton.enabled=YES;self.pauseButton.enabled=NO;self.stopButton.enabled=NO;self.recordButton.alpha=1;self.pauseButton.alpha=.35;self.stopButton.alpha=.35;return;}NSDictionary*d=NKParseKV(o);NSString*state=d[@"state"]?:@"idle";'
if old not in s:
    raise SystemExit('Recorder refreshStatus marker missing')
s = s.replace(old, new, 1)
settings.write_text(s)

print('Applied NKTouch 0.7.5.3.1 Recorder rootless hotfix')
