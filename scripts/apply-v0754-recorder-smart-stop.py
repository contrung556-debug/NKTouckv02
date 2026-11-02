#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: apply-v0754-recorder-smart-stop.py <upstream-dir>')

root = Path(sys.argv[1])
settings = root / 'zxtouch/zxtouch/Settings/SettingsPageViewController.m'
rec = root / 'layout/usr/bin/nkrecorder'
exporter = root / 'layout/usr/share/nktouch/nkrecorder.lua'
for p in (settings, rec, exporter):
    if not p.exists():
        raise SystemExit(f'missing prepared file: {p}')

# ---- Recorder shell: add one-shot finish => stop + trim tail + render Lua ----
r = rec.read_text()
r = r.replace('VERSION="0.7.5.2"', 'VERSION="0.7.5.4"', 1)
finish_case = r'''
  finish)
    [ "$#" -le 2 ] || { echo "usage: nkrecorder finish [trim_count] [name]" >&2; exit 2; }
    mkdir_state; need_runtime
    mode="$(read_mode)"
    [ "$mode" = recording ] || [ "$mode" = paused ] || { echo "NKTouch Recorder V4: no active recording" >&2; exit 3; }
    trim="${1:-1}"
    case "$trim" in ''|*[!0-9]*) echo "NKTouch Recorder V4: invalid trim count" >&2; exit 2;; esac
    if [ "$mode" = recording ]; then
      "$CORE" record stop >/dev/null
      append_current_segment
    fi
    [ -s "$SEGMENTS" ] || { clear_session; echo "NKTouch Recorder V4: no recording segments" >&2; exit 5; }
    if [ "$#" -eq 2 ]; then
      base="$(safe_name "$2")"
      [ -n "$base" ] || { echo "NKTouch Recorder V4: invalid name" >&2; exit 2; }
      base="${base%.lua}"; base="${base%.nktl}"
    else
      base="$(session_name)"
    fi
    merged="$STATE/merged.raw"
    : > "$merged"
    while IFS= read -r raw; do
      [ -f "$raw" ] || continue
      cat "$raw" >> "$merged"
      printf '\n' >> "$merged"
    done < "$SEGMENTS"
    timeline="$OUT/$base.nktl"
    "$LUA" "$EXPORTER" timeline "$merged" "$timeline" >/dev/null
    if [ "$trim" -gt 0 ]; then
      "$LUA" "$EXPORTER" trim-tail "$timeline" "$trim" >/dev/null
    fi
    script="$SCRIPTS/$base.lua"
    "$LUA" "$EXPORTER" render "$timeline" "$script" >/dev/null
    clear_session
    echo "state=stopped"
    echo "timeline=$timeline"
    echo "script=$script"
    echo "name=$base"
    echo "trimmed=$trim"
    ;;
'''
if '  finish)' not in r:
    anchor = '  cancel)\n'
    if anchor not in r:
        raise SystemExit('nkrecorder cancel marker missing')
    r = r.replace(anchor, finish_case + '\n' + anchor, 1)
r = r.replace('  nkrecorder stop [name]\n', '  nkrecorder stop [name]\n  nkrecorder finish [trim_count] [name]\n', 1)
r = r.replace('NKTouch Recorder V3 v0.7.5.2', 'NKTouch Recorder V4 v0.7.5.4')
rec.write_text(r)

# ---- Lua exporter: support safe tail trimming before automatic render ----
l = exporter.read_text()
l = l.replace('-- NKTouch Recorder V3 exporter v0.7.5.2', '-- NKTouch Recorder V4 exporter v0.7.5.4', 1)
l = l.replace('local VERSION = "0.7.5.2"', 'local VERSION = "0.7.5.4"', 1)
trim_fn = r'''
local function trim_tail(path, count)
  local rows, err = read_timeline(path)
  if not rows then return nil, err end
  count = tonumber(count)
  if not count or count < 0 or count ~= math.floor(count) then return nil, "invalid trim count" end
  local removed = 0
  while removed < count and #rows > 0 do
    table.remove(rows, #rows)
    removed = removed + 1
  end
  local ok, werr = write_timeline(path, rows, "smart-stop", 0)
  if not ok then return nil, werr end
  return {actions=#rows, trimmed=removed}
end

'''
if 'local function trim_tail(path, count)' not in l:
    anchor = 'local function move_row(path, from_i, to_i)\n'
    pos = l.find(anchor)
    if pos < 0:
        raise SystemExit('Lua move_row marker missing')
    l = l[:pos] + trim_fn + l[pos:]
main_anchor = '  if cmd == "move" and argv[2] and argv[3] and argv[4] and not argv[5] then\n'
trim_cmd = r'''  if cmd == "trim-tail" and argv[2] and argv[3] and not argv[4] then
    local r, err = trim_tail(argv[2], argv[3]); if not r then io.stderr:write("nkrecorder-v4: ", tostring(err), "\n"); return 3 end
    print("actions=" .. r.actions); print("trimmed=" .. r.trimmed); return 0
  end
'''
if 'cmd == "trim-tail"' not in l:
    if main_anchor not in l:
        raise SystemExit('Lua main move marker missing')
    l = l.replace(main_anchor, trim_cmd + main_anchor, 1)
exporter.write_text(l)

# ---- Native UI: foreground smart stop + automatic Lua + Editor ----
s = settings.read_text()
marker = '// V0.7.5.4 Recorder V4: foreground smart-stop, tail trim and automatic Lua render.\n'
if marker not in s:
    insert_after = '// V0.7.5.3.3 Recorder status fix: valid status exits zero without requiring a previous timeline.\n'
    if insert_after in s:
        s = s.replace(insert_after, insert_after + marker, 1)
    else:
        s = marker + s

s = s.replace('self.title=@"Recorder V3";', 'self.title=@"Recorder V4";', 1)
s = s.replace('title.text=@"Ghi thao tác thật";', 'title.text=@"Ghi thông minh";', 1)
s = s.replace('self.detailLabel.text=@"Tap / Hold / Swipe + timing";', 'self.detailLabel.text=@"Quay lại NKTouch = Stop + Lua";', 1)
s = s.replace('UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Recorder V3"', 'UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Recorder V4"')

prop_anchor = '@property(nonatomic,strong)NSTimer *statusTimer;\n'
props = '''@property(nonatomic,strong)NSTimer *statusTimer;\n@property(nonatomic,assign)BOOL smartStopArmed;\n@property(nonatomic,assign)BOOL leftAppWhileRecording;\n@property(nonatomic,assign)BOOL smartFinishing;\n'''
if '@property(nonatomic,assign)BOOL smartStopArmed;' not in s:
    if prop_anchor not in s:
        raise SystemExit('Recorder property marker missing')
    s = s.replace(prop_anchor, props, 1)

init_anchor = 'self.actions=@[];[self refreshStatus];[self loadLatest];self.statusTimer=[NSTimer scheduledTimerWithTimeInterval:.8 target:self selector:@selector(refreshStatus) userInfo:nil repeats:YES];[[NSRunLoop mainRunLoop]addTimer:self.statusTimer forMode:NSRunLoopCommonModes];\n'
init_new = '''self.actions=@[];self.smartStopArmed=NO;self.leftAppWhileRecording=NO;self.smartFinishing=NO;\n    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(nkRecorderDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];\n    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(nkRecorderDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];\n    [self refreshStatus];[self loadLatest];self.statusTimer=[NSTimer scheduledTimerWithTimeInterval:.8 target:self selector:@selector(refreshStatus) userInfo:nil repeats:YES];[[NSRunLoop mainRunLoop]addTimer:self.statusTimer forMode:NSRunLoopCommonModes];\n'''
if 'nkRecorderDidEnterBackground:' not in s:
    if init_anchor not in s:
        raise SystemExit('Recorder init marker missing')
    s = s.replace(init_anchor, init_new, 1)

view_disappear = '- (void)viewWillDisappear:(BOOL)animated{[self.statusTimer invalidate];self.statusTimer=nil;[super viewWillDisappear:animated];}\n'
view_disappear_new = view_disappear + '- (void)dealloc{[[NSNotificationCenter defaultCenter]removeObserver:self];}\n'
if '- (void)dealloc{[[NSNotificationCenter defaultCenter]removeObserver:self];}' not in s:
    if view_disappear not in s:
        raise SystemExit('Recorder viewWillDisappear marker missing')
    s = s.replace(view_disappear, view_disappear_new, 1)

old_refresh = '- (void)refreshStatus{__weak typeof(self)w=self;[self run:@[@"status"] done:^(int c,NSString*o){typeof(self)self=w;if(!self||c!=0)return;'
new_refresh = '- (void)refreshStatus{if(self.smartFinishing)return;__weak typeof(self)w=self;[self run:@[@"status"] done:^(int c,NSString*o){typeof(self)self=w;if(!self||c!=0)return;'
if old_refresh in s:
    s = s.replace(old_refresh, new_refresh, 1)

old_record = '- (void)recordTapped{__weak typeof(self)w=self;[self run:@[@"start"] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;[self refreshStatus];if(c==0){UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Recorder đang chạy" message:@"Chuyển sang app cần ghi. Khi cần nghỉ, quay lại NKTouch và bấm Pause." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}else [self showRecorderError:o];}];}\n'
new_record = '''- (void)recordTapped{__weak typeof(self)w=self;[self run:@[@"start"] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;if(c==0){self.recState=@"recording";self.smartStopArmed=YES;self.leftAppWhileRecording=NO;self.smartFinishing=NO;[self refreshStatus];UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Smart Recorder đang chạy" message:@"Sang app cần ghi và thao tác bình thường. Khi xong chỉ cần quay lại NKTouch — Recorder sẽ tự dừng, bỏ thao tác quay về, sinh Lua và mở Editor." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addAction:[UIAlertAction actionWithTitle:@"Bắt đầu" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}else [self showRecorderError:o];}];}\n'''
if old_record not in s:
    raise SystemExit('recordTapped marker missing')
s = s.replace(old_record, new_record, 1)

old_stop_start = '- (void)stopTapped{UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Dừng và tạo Timeline"'
stop_start = s.find(old_stop_start)
show_err = s.find('- (void)showRecorderError:', stop_start)
if stop_start < 0 or show_err < 0:
    raise SystemExit('stopTapped block marker missing')
new_methods = r'''- (void)nkRecorderDidEnterBackground:(NSNotification*)n{(void)n;if(self.smartStopArmed&&[self.recState isEqualToString:@"recording"])self.leftAppWhileRecording=YES;}
- (void)nkRecorderDidBecomeActive:(NSNotification*)n{(void)n;if(!self.smartStopArmed||!self.leftAppWhileRecording||self.smartFinishing)return;__weak typeof(self)w=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.12*NSEC_PER_SEC)),dispatch_get_main_queue(),^{typeof(self)self=w;if(!self||self.smartFinishing)return;if([self.recState isEqualToString:@"recording"])[self smartFinishWithTrim:1];});}
- (void)openGeneratedScript:(NSString*)path{NSString*name=path.lastPathComponent;if(!name.length){[self showRecorderError:@"Đã dừng nhưng không tìm thấy file Lua."];return;}Class cls=NSClassFromString(@"NKLuaEditorViewController");UIViewController*editor=[[cls alloc]init];[editor setValue:name forKey:@"scriptName"];editor.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:editor animated:YES];}
- (void)smartFinishWithTrim:(NSInteger)trim{if(self.smartFinishing)return;self.smartFinishing=YES;self.smartStopArmed=NO;self.leftAppWhileRecording=NO;self.stateLabel.text=@"● ĐANG TẠO LUA…";self.stateLabel.textColor=NKBlue();self.recordButton.enabled=NO;self.pauseButton.enabled=NO;self.stopButton.enabled=NO;NSString*t=[NSString stringWithFormat:@"%ld",(long)MAX(0,trim)];__weak typeof(self)w=self;[self run:@[@"finish",t] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;self.smartFinishing=NO;if(c!=0){[self showRecorderError:o];[self refreshStatus];return;}NSDictionary*d=NKParseKV(o);self.timelinePath=d[@"timeline"];NSString*script=d[@"script"];self.recState=@"idle";self.stateLabel.text=@"✓ ĐÃ TẠO LUA";self.stateLabel.textColor=NKGreen();self.detailLabel.text=[NSString stringWithFormat:@"Đã bỏ %@ thao tác cuối • %@",d[@"trimmed"]?:@"0",script.lastPathComponent?:@"script.lua"];[self reloadTimeline];[self refreshStatus];if(script.length){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.18*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self openGeneratedScript:script];});}}];}
- (void)stopTapped{NSInteger trim=[self.recState isEqualToString:@"paused"]?0:1;[self smartFinishWithTrim:trim];}
'''
s = s[:stop_start] + new_methods + s[show_err:]

# Convert remains useful after timeline edits, but relabel it as rebuild.
s = s.replace('self.convertButton=[self nkRecorderButton:@"Convert → Lua"', 'self.convertButton=[self nkRecorderButton:@"Rebuild Lua"', 1)
s = s.replace('self.title=@"Recorder V3"', 'self.title=@"Recorder V4"')
s = s.replace('NKTouch 0.7.5.3.3', 'NKTouch 0.7.5.4')
s = s.replace('nkLabel:@"0.7.5.3.3"', 'nkLabel:@"0.7.5.4"')
s = s.replace('text:@"0.7.5.3.3"', 'text:@"0.7.5.4"')
settings.write_text(s)

print('Applied NKTouch 0.7.5.4 Recorder V4 smart-stop + auto Lua flow')
