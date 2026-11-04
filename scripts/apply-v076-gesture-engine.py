#!/usr/bin/env python3
"""Layer Recorder V6 Gesture Engine over the proven V5/V0.7.5.6 build.

Only the staged exporter and Recorder screen are transformed. Core recording,
SpringBoard volume hotkey, daemon, and Editor/Task/Network behavior stay intact.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v076-gesture-engine.py <upstream-dir>")

root = Path(sys.argv[1])
exporter = root / "layout/usr/share/nktouch/nkrecorder.lua"
settings = root / "zxtouch/zxtouch/Settings/SettingsPageViewController.m"
for path in (exporter, settings):
    if not path.is_file():
        raise SystemExit(f"missing staged file: {path}")

def replace_between(text, begin, end, replacement):
    if text.count(begin) != 1 or text.count(end) != 1:
        raise SystemExit(f"unexpected gesture patch anchors: {begin} / {end}")
    a, b = text.index(begin), text.index(end)
    if a >= b:
        raise SystemExit(f"gesture patch anchors out of order: {begin}")
    return text[:a] + replacement + text[b:]

s = exporter.read_text()
if 'local VERSION = "0.7.5.4"' not in s or 'local function trim_tail(path, count)' not in s:
    raise SystemExit("V4 exporter with tail-trim required for Recorder V6")
s = s.replace('local VERSION = "0.7.5.4"', 'local VERSION = "0.7.6"', 1)
s = s.replace('-- NKTouch Recorder V4 exporter v0.7.5.4',
              '-- NKTouch Recorder V6 Gesture Engine v0.7.6', 1)
s = replace_between(s, 'local function parse_raw(path)', 'local function normalize_action(a)',
                    'local gesture = require("nkgesture_v6")\nlocal parse_raw = gesture.parseRaw\n\n')
s = replace_between(s, 'local function normalize_action(a)', 'local function write_timeline(path, rows, source, ignored)',
                    'local normalize_row = gesture.normalizeRow\n\n')
s = replace_between(s, 'local function write_timeline(path, rows, source, ignored)', 'local function split_tabs(line)',
                    'local write_timeline = gesture.writeTimeline\n\n')
s = replace_between(s, 'local function read_timeline(path)', 'local function timeline_from_raw(raw_path, timeline_path)',
                    'local read_timeline = gesture.readTimeline\n\n')
s = replace_between(s, 'local function inspect(path)', 'local function parse_assignment(s)',
                    'local inspect = gesture.inspect\n\n')
s = replace_between(s, 'local function render_lua(timeline_path, out_path)', 'local function print_result(r)',
                    'local render_lua = gesture.renderLua\n\n')

# Retain V3/V4 editor and trim-tail functionality. Path data is invalidated when
# the user edits endpoints, action type or duration; a legacy straight swipe
# remains safe instead of accidentally replaying mismatching coordinates.
s = s.replace('  local allowed = {action=true,idle_ms=true,duration_ms=true,x1=true,y1=true,x2=true,y2=true}\n',
              '  local allowed = {action=true,idle_ms=true,duration_ms=true,x1=true,y1=true,x2=true,y2=true}\n  local resetPath = false\n', 1)
s = s.replace('    row[k] = v\n', '''    row[k] = v
    if k == "action" or k == "duration_ms" or k == "x1" or k == "y1" or k == "x2" or k == "y2" then
      resetPath = true
    end
''', 1)
s = s.replace('  local normalized, nerr = normalize_row(row)\n',
              '  if resetPath then row.path = "" end\n  local normalized, nerr = normalize_row(row)\n', 1)

old_counts = 'local counts = {tap = 0, hold = 0, swipe = 0}'
if old_counts not in s:
    raise SystemExit("V4 timeline action-count anchor missing")
s = s.replace(old_counts, 'local counts = {tap = 0, hold = 0, swipe = 0, drag = 0}', 1)
s = s.replace('swipe = counts.swipe, ignored = ignored_or_err or 0}',
              'swipe = counts.swipe, drag = counts.drag, ignored = ignored_or_err or 0}', 1)
s = s.replace('"tap","hold","swipe","ignored"', '"tap","hold","swipe","drag","ignored"', 1)
# print_result includes the V3 action count labels with no whitespace.
if '"drag"' not in s[s.index('local function print_result(r)'):s.index('local function main(argv)')]:
    raise SystemExit("V6 drag status missing from exporter")
exporter.write_text(s)

u = settings.read_text()
if 'NKRecorderV3ViewController' not in u or 'Recorder V5' not in u:
    raise SystemExit("V5 Recorder screen required")
u = u.replace('self.title=@"Recorder V5";', 'self.title=@"Recorder V6";', 1)
u = u.replace('title.text=@"Ghi như AutoTouch";',
              'title.text=@"Ghi thao tác • Gesture V6";', 1)
u = u.replace('Tap / Hold / Swipe', 'Tap / Hold / Swipe / Drag')
u = u.replace('@"Đổi loại Tap / Hold / Swipe"', '@"Đổi loại Tap / Hold / Swipe / Drag"')
u = u.replace('@[@"tap",@"hold",@"swipe"]', '@[@"tap",@"hold",@"swipe",@"drag"]', 1)
u = u.replace('[d[@"action"] isEqualToString:@"swipe"]',
              '([d[@"action"] isEqualToString:@"swipe"]||[d[@"action"] isEqualToString:@"drag"])')
u = u.replace('NKTouch 0.7.5.6', 'NKTouch 0.7.6')
u = u.replace('nkLabel:@"0.7.5.6"', 'nkLabel:@"0.7.6"')
u = u.replace('text:@"0.7.5.6"', 'text:@"0.7.6"')
settings.write_text(u)
print("Applied NKTouch 0.7.6 Recorder V6 Gesture Engine")
