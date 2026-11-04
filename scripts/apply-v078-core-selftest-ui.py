#!/usr/bin/env python3
"""Patch the staged NKTouch home Self Test to run the bundled Core Self-Test.

This updates only the existing user-facing Self Test action, not Recorder,
SpringBoard's command protocol or script execution semantics.
"""
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v078-core-selftest-ui.py <upstream-directory>")
root = Path(sys.argv[1])
path = root / "zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if not path.exists():
    raise SystemExit(f"missing NKTouch app Settings UI: {path}")
src = path.read_text()
start = src.find("- (void)runSelfTest {")
end = src.find("- (void)recordInfo {", start)
if start < 0 or end < 0:
    raise SystemExit("expected v0.7.7 Self Test action not found")
method = src[start:end]
old = re.compile(
    r'NSString \*body=@"local nk=require\(.*?'
    r'NSError \*err=nil;BOOL wrote=\[body writeToFile:path '
    r'atomically:YES encoding:NSUTF8StringEncoding error:&err\];', re.S
)
replacement = (
    'NSError *err=nil;NSString *body=[NSString stringWithContentsOfFile:'
    '@"/var/jb/usr/share/nktouch/lua/nkcore_selftest.lua" '
    'encoding:NSUTF8StringEncoding error:&err];'
    'BOOL wrote=body.length>0&&[body writeToFile:path atomically:YES '
    'encoding:NSUTF8StringEncoding error:&err];'
)
method, count = old.subn(lambda _: replacement, method, count=1)
if count != 1:
    raise SystemExit(f"cannot replace staged Self Test script: {count}")
if '[SELFTEST] task=ok' not in method:
    raise SystemExit("existing Self Test log marker missing")
method = method.replace('[SELFTEST] task=ok', '[NKCORE][SUMMARY] status=PASS')
method = method.replace('for(int i=0;i<50;i++', 'for(int i=0;i<120;i++')
method = method.replace('message:@"Đang kiểm tra Lua → nktask → Logs…"',
                        'message:@"Đang kiểm tra Lua, màn hình và màu sắc…"')
method = method.replace('withTitle:@"Self Test"', 'withTitle:@"Core Self-Test"')
method = method.replace('@"Self Test hoàn tất"', '@"Core Self-Test: PASS"')
method = method.replace('@"Self Test phát hiện lỗi"', '@"Core Self-Test: FAIL"')
method = method.replace('Lua syntax: %@\\nTask doctor: %@\\nTask run: %@\\nFinal state: %@\\nLogs: %@',
                        'Lua: %@\\nRuntime: %@\\nTest run: %@\\nState: %@\\nCore checks: %@')
if 'stringWithContentsOfFile:' not in method or '[NKCORE][SUMMARY] status=PASS' not in method:
    raise SystemExit("Core Self-Test staging patch lost its verification marker")
src = src[:start] + method + src[end:]
src = src.replace('@"Self Test"', '@"Core Self-Test"', 1)
path.write_text(src)
print("Applied v0.7.8 on-device Core Self-Test UI")
