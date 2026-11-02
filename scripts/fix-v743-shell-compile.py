#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: fix-v743-shell-compile.py <upstream-dir>")

root = Path(sys.argv[1])
settings = root / "zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if not settings.exists():
    raise SystemExit("missing generated SettingsPageViewController.m")

s = settings.read_text()

# Python re.sub interprets backslash escapes in a replacement string. The shell
# transformer intentionally emits a two-line subtitle using \n, but re.sub turns
# it into a literal source-code newline. Convert it back to an Objective-C escape.
bad = '@"Viết • Check • Run • Debug\nKhông cần rời NKTouch"'
good = '@"Viết • Check • Run • Debug\\nKhông cần rời NKTouch"'
if bad in s:
    s = s.replace(bad, good, 1)
elif good not in s:
    raise SystemExit("Lua Studio subtitle marker missing")

# SettingsPageViewController owns _tableView as an ivar, not a UITableViewController
# tableView property. Keep the shell theme code compatible with the upstream class.
s = s.replace('self.tableView.backgroundColor = NKShellBG();', '_tableView.backgroundColor = NKShellBG();')

settings.write_text(s)

check = settings.read_text()
if bad in check:
    raise SystemExit("literal newline still present inside Lua Studio Objective-C string")
if good not in check:
    raise SystemExit("escaped Lua Studio subtitle missing")
if 'self.tableView.backgroundColor = NKShellBG();' in check:
    raise SystemExit("invalid Settings tableView property reference remains")
if '_tableView.backgroundColor = NKShellBG();' not in check:
    raise SystemExit("Settings table background theme missing")

print("NKTouch v0.7.4.3 generated shell compile fixes applied")
