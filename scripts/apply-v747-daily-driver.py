#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v747-daily-driver.py <upstream-dir>")

root = Path(sys.argv[1])
settings = root / "zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if not settings.exists():
    raise SystemExit("missing SettingsPageViewController.m")

s = settings.read_text()
if "V7.4.7 daily driver" in s:
    print("V7.4.7 daily driver already applied")
    raise SystemExit(0)

# Release marker + displayed version. Keep native task supervisor core at V7.0.
anchor = '// V7.4.6 direct Lua spawn fix: nktask -> lua54, no shell-wrapper dependency.\n'
marker = '// V7.4.7 daily driver: Self Test + Task Center + editor/log quality-of-life.\n'
if anchor in s:
    s = s.replace(anchor, anchor + marker, 1)
else:
    s = marker + s
for old in ('7.4.3', '7.4.4', '7.4.5', '7.4.6'):
    s = s.replace(f'nkLabel:@"{old}"', 'nkLabel:@"7.4.7"')
s = s.replace('NKTouch 0.7.4.6', 'NKTouch 0.7.4.7')
s = s.replace('text:@"7.4.6"', 'text:@"7.4.7"')

# NKLuaRun already routes Check/Run/task lifecycle directly. Extend its native
# nktask route for Task Center and Self Test diagnostics.
old_cmds = '[@[@"status", @"pause", @"resume", @"stop", @"logs"] containsObject:cmd]'
new_cmds = '[@[@"status", @"pause", @"resume", @"stop", @"logs", @"list", @"doctor", @"version"] containsObject:cmd]'
if old_cmds not in s:
    raise SystemExit('NKLuaRun task command marker missing')
s = s.replace(old_cmds, new_cmds, 1)

old_forward = '@class NKLuaLibraryViewController, NKLuaToolsViewController, NKAIPromptViewController;'
new_forward = '@class NKLuaLibraryViewController, NKLuaToolsViewController, NKAIPromptViewController, NKTaskCenterViewController, NKTaskDetailViewController;'
if old_forward not in s:
    raise SystemExit('forward class marker missing')
s = s.replace(old_forward, new_forward, 1)

# Task Center is intentionally UI-only: it consumes the retained nktask list,
# status, logs and stop contracts. No task-engine protocol changes are made.
task_center = r'''
#pragma mark - Task Center
static UIColor *NKTaskStateColor(NSString *state) {
    NSString *v=state.lowercaseString?:@"";
    if([v isEqualToString:@"success"])return NKGreen();
    if([v isEqualToString:@"failed"]||[v isEqualToString:@"timeout"])return NKRed();
    if([v isEqualToString:@"paused"])return NKC(0xFFB545);
    if([v isEqualToString:@"stopped"])return NKMuted();
    return NKBlue();
}

@interface NKTaskDetailViewController : UIViewController
@property(nonatomic,copy) NSString *taskID;
@property(nonatomic,strong) UILabel *stateLabel;
@property(nonatomic,strong) UILabel *scriptLabel;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UIButton *stopButton;
- (instancetype)initWithTaskID:(NSString*)taskID;
@end

@implementation NKTaskDetailViewController
- (instancetype)initWithTaskID:(NSString*)taskID{self=[super init];if(self){self.taskID=taskID;self.hidesBottomBarWhenPushed=YES;}return self;}
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"Chi tiết tác vụ";self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;self.view.backgroundColor=NKBG();if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadTask)];
    UIView *head=[[UIView alloc]init];head.translatesAutoresizingMaskIntoConstraints=NO;NKCard(head,14);
    UILabel *idLabel=[[UILabel alloc]init];idLabel.translatesAutoresizingMaskIntoConstraints=NO;idLabel.text=self.taskID;idLabel.textColor=NKMuted();idLabel.font=[UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    self.stateLabel=[[UILabel alloc]init];self.stateLabel.translatesAutoresizingMaskIntoConstraints=NO;self.stateLabel.text=@"Đang tải…";self.stateLabel.textColor=NKBlue();self.stateLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.scriptLabel=[[UILabel alloc]init];self.scriptLabel.translatesAutoresizingMaskIntoConstraints=NO;self.scriptLabel.text=@"—";self.scriptLabel.textColor=UIColor.whiteColor;self.scriptLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [head addSubview:self.stateLabel];[head addSubview:self.scriptLabel];[head addSubview:idLabel];
    self.logView=[[UITextView alloc]init];self.logView.translatesAutoresizingMaskIntoConstraints=NO;self.logView.editable=NO;self.logView.backgroundColor=NKC(0x090E1C);self.logView.textColor=NKC(0xD9E4FF);self.logView.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];self.logView.layer.cornerRadius=13;self.logView.layer.borderWidth=1;self.logView.layer.borderColor=NKBorder().CGColor;self.logView.textContainerInset=UIEdgeInsetsMake(12,12,12,12);
    UIButton *copy=[UIButton buttonWithType:UIButtonTypeSystem];copy.translatesAutoresizingMaskIntoConstraints=NO;[copy setTitle:@"Sao chép Log" forState:UIControlStateNormal];copy.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];[copy addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton=[UIButton buttonWithType:UIButtonTypeSystem];self.stopButton.translatesAutoresizingMaskIntoConstraints=NO;[self.stopButton setTitle:@"Dừng tác vụ" forState:UIControlStateNormal];self.stopButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightBold];[self.stopButton setTitleColor:NKRed() forState:UIControlStateNormal];[self.stopButton addTarget:self action:@selector(stopTask) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons=[[UIStackView alloc]initWithArrangedSubviews:@[copy,self.stopButton]];buttons.translatesAutoresizingMaskIntoConstraints=NO;buttons.axis=UILayoutConstraintAxisHorizontal;buttons.spacing=10;buttons.distribution=UIStackViewDistributionFillEqually;
    [self.view addSubview:head];[self.view addSubview:self.logView];[self.view addSubview:buttons];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[head.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],[head.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],[head.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],[head.heightAnchor constraintEqualToConstant:92],[self.stateLabel.leadingAnchor constraintEqualToAnchor:head.leadingAnchor constant:14],[self.stateLabel.topAnchor constraintEqualToAnchor:head.topAnchor constant:12],[self.scriptLabel.leadingAnchor constraintEqualToAnchor:self.stateLabel.leadingAnchor],[self.scriptLabel.topAnchor constraintEqualToAnchor:self.stateLabel.bottomAnchor constant:7],[idLabel.leadingAnchor constraintEqualToAnchor:self.stateLabel.leadingAnchor],[idLabel.topAnchor constraintEqualToAnchor:self.scriptLabel.bottomAnchor constant:5],[buttons.leadingAnchor constraintEqualToAnchor:head.leadingAnchor],[buttons.trailingAnchor constraintEqualToAnchor:head.trailingAnchor],[buttons.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],[buttons.heightAnchor constraintEqualToConstant:40],[self.logView.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:10],[self.logView.leadingAnchor constraintEqualToAnchor:head.leadingAnchor],[self.logView.trailingAnchor constraintEqualToAnchor:head.trailingAnchor],[self.logView.bottomAnchor constraintEqualToAnchor:buttons.topAnchor constant:-10]]];
    [self reloadTask];
}
- (void)reloadTask{
    NSString *task=self.taskID;__weak typeof(self)w=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{int sc=0,lc=0;NSString *status=NKLuaRun(@[@"status",task],&sc);NSString *logs=NKLuaRun(@[@"logs",task,@"200"],&lc);NSDictionary *d=NKParseKV(status);dispatch_async(dispatch_get_main_queue(),^{typeof(self)self=w;if(!self)return;NSString *state=d[@"state"]?:@"unknown";self.stateLabel.text=[NSString stringWithFormat:@"● %@",state.uppercaseString];self.stateLabel.textColor=NKTaskStateColor(state);self.scriptLabel.text=[d[@"script"] lastPathComponent]?:@"Script không xác định";self.logView.text=lc==0?logs:[NSString stringWithFormat:@"%@\n\n%@",status,logs?:@""];BOOL active=NKTaskStateIsActive(state);self.stopButton.enabled=active;self.stopButton.alpha=active?1:.35;if(self.logView.text.length)[self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length-1,1)];});});
}
- (void)copyLog{[UIPasteboard generalPasteboard].string=self.logView.text?:@"";}
- (void)stopTask{
    NSString *task=self.taskID;__weak typeof(self)w=self;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{int c=0;NSString *o=NKLuaRun(@[@"stop",task],&c);dispatch_async(dispatch_get_main_queue(),^{typeof(self)self=w;if(!self)return;if(c!=0){UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Không dừng được" message:o preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}else{[self reloadTask];}});});
}
@end

@interface NKTaskCenterViewController : UITableViewController
@property(nonatomic,strong) NSArray<NSDictionary*> *tasks;
@end
@implementation NKTaskCenterViewController
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"Task Center";self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;self.tableView.backgroundColor=NKBG();self.tableView.separatorColor=NKBorder();if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadTasks)];
    self.refreshControl=[[UIRefreshControl alloc]init];[self.refreshControl addTarget:self action:@selector(reloadTasks) forControlEvents:UIControlEventValueChanged];[self reloadTasks];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadTasks];}
- (void)reloadTasks{
    __weak typeof(self)w=self;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{int c=0;NSString *out=NKLuaRun(@[@"list"],&c);NSMutableArray *rows=[NSMutableArray array];if(c==0){[out enumerateLinesUsingBlock:^(NSString *line,BOOL *stop){(void)stop;if(!line.length||[line isEqualToString:@"no_tasks"])return;NSArray *p=[line componentsSeparatedByString:@"\t"];if(p.count>=3)[rows addObject:@{@"id":p[0],@"state":p[1],@"script":[p[2] lastPathComponent]?:p[2]}];}];}dispatch_async(dispatch_get_main_queue(),^{typeof(self)self=w;if(!self)return;self.tasks=rows;[self.tableView reloadData];[self.refreshControl endRefreshing];});});
}
- (NSInteger)tableView:(UITableView*)tv numberOfRowsInSection:(NSInteger)section{(void)tv;(void)section;return MAX((NSInteger)self.tasks.count,1);}
- (UITableViewCell*)tableView:(UITableView*)tv cellForRowAtIndexPath:(NSIndexPath*)ip{
    UITableViewCell *cell=[tv dequeueReusableCellWithIdentifier:@"task"];if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"task"];cell.backgroundColor=NKPanel();cell.textLabel.textColor=UIColor.whiteColor;cell.detailTextLabel.textColor=NKMuted();cell.accessoryType=UITableViewCellAccessoryNone;
    if(!self.tasks.count){cell.textLabel.text=@"Chưa có lịch sử tác vụ";cell.detailTextLabel.text=@"Chạy một script để Task Center ghi nhận.";cell.imageView.image=NKIcon(@"tray",18);cell.imageView.tintColor=NKMuted();return cell;}
    NSDictionary *d=self.tasks[ip.row];NSString *state=d[@"state"]?:@"unknown";cell.textLabel.text=d[@"script"]?:@"Script";cell.detailTextLabel.text=[NSString stringWithFormat:@"%@  •  %@",state.uppercaseString,d[@"id"]?:@""];cell.imageView.image=NKIcon(NKTaskStateIsActive(state)?@"bolt.circle.fill":([state isEqualToString:@"success"]?@"checkmark.circle.fill":@"clock.arrow.circlepath"),18);cell.imageView.tintColor=NKTaskStateColor(state);cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{[tv deselectRowAtIndexPath:ip animated:YES];if(ip.row>=self.tasks.count)return;NSString *task=self.tasks[ip.row][@"id"];if(task.length)[self.navigationController pushViewController:[[NKTaskDetailViewController alloc]initWithTaskID:task] animated:YES];}
@end

'''
marker_dashboard = '#pragma mark - Dashboard\n'
if marker_dashboard not in s:
    raise SystemExit('dashboard marker missing')
s = s.replace(marker_dashboard, task_center + marker_dashboard, 1)

# Home: add Task Center + Self Test as first-class daily-driver actions.
old_cards = '''    NKMenuCard *rec=[[NKMenuCard alloc]initWithIcon:@"record.circle.fill" title:@"Recorder" subtitle:@"Ghi thao tác" tint:NKRed()];
    NKMenuCard *tools=[[NKMenuCard alloc]initWithIcon:@"wrench.and.screwdriver.fill" title:@"Công cụ" subtitle:@"Format, mẫu, tiện ích" tint:NKPurple()];
    [lib addTarget:self action:@selector(openWorkspace) forControlEvents:UIControlEventTouchUpInside];[api addTarget:self action:@selector(openTools) forControlEvents:UIControlEventTouchUpInside];[tools addTarget:self action:@selector(openTools) forControlEvents:UIControlEventTouchUpInside];[rec addTarget:self action:@selector(recordInfo) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *r1=[[UIStackView alloc]initWithArrangedSubviews:@[lib,api]];r1.axis=UILayoutConstraintAxisHorizontal;r1.spacing=10;r1.distribution=UIStackViewDistributionFillEqually;[r1.heightAnchor constraintEqualToConstant:108].active=YES;
    UIStackView *r2=[[UIStackView alloc]initWithArrangedSubviews:@[rec,tools]];r2.axis=UILayoutConstraintAxisHorizontal;r2.spacing=10;r2.distribution=UIStackViewDistributionFillEqually;[r2.heightAnchor constraintEqualToConstant:108].active=YES;
'''
new_cards = '''    NKMenuCard *rec=[[NKMenuCard alloc]initWithIcon:@"record.circle.fill" title:@"Recorder" subtitle:@"Ghi thao tác" tint:NKRed()];
    NKMenuCard *tools=[[NKMenuCard alloc]initWithIcon:@"wrench.and.screwdriver.fill" title:@"Công cụ" subtitle:@"Format, mẫu, tiện ích" tint:NKPurple()];
    NKMenuCard *tasks=[[NKMenuCard alloc]initWithIcon:@"list.bullet.rectangle.portrait.fill" title:@"Task Center" subtitle:@"Lịch sử, Logs, Stop" tint:NKC(0x57D6FF)];
    NKMenuCard *selftest=[[NKMenuCard alloc]initWithIcon:@"stethoscope" title:@"Self Test" subtitle:@"Kiểm tra Lua + Task" tint:NKGreen()];
    [lib addTarget:self action:@selector(openWorkspace) forControlEvents:UIControlEventTouchUpInside];[api addTarget:self action:@selector(openTools) forControlEvents:UIControlEventTouchUpInside];[tools addTarget:self action:@selector(openTools) forControlEvents:UIControlEventTouchUpInside];[rec addTarget:self action:@selector(recordInfo) forControlEvents:UIControlEventTouchUpInside];[tasks addTarget:self action:@selector(openTaskCenter) forControlEvents:UIControlEventTouchUpInside];[selftest addTarget:self action:@selector(runSelfTest) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *r1=[[UIStackView alloc]initWithArrangedSubviews:@[lib,api]];r1.axis=UILayoutConstraintAxisHorizontal;r1.spacing=10;r1.distribution=UIStackViewDistributionFillEqually;[r1.heightAnchor constraintEqualToConstant:108].active=YES;
    UIStackView *r2=[[UIStackView alloc]initWithArrangedSubviews:@[rec,tools]];r2.axis=UILayoutConstraintAxisHorizontal;r2.spacing=10;r2.distribution=UIStackViewDistributionFillEqually;[r2.heightAnchor constraintEqualToConstant:108].active=YES;
    UIStackView *r3=[[UIStackView alloc]initWithArrangedSubviews:@[tasks,selftest]];r3.axis=UILayoutConstraintAxisHorizontal;r3.spacing=10;r3.distribution=UIStackViewDistributionFillEqually;[r3.heightAnchor constraintEqualToConstant:108].active=YES;
'''
if old_cards not in s:
    raise SystemExit('home cards marker missing')
s = s.replace(old_cards, new_cards, 1)
old_stack = '[stack addArrangedSubview:header];[stack addArrangedSubview:hero];[stack addArrangedSubview:task];[stack addArrangedSubview:r1];[stack addArrangedSubview:r2];[stack addArrangedSubview:health];'
new_stack = '[stack addArrangedSubview:header];[stack addArrangedSubview:hero];[stack addArrangedSubview:task];[stack addArrangedSubview:r1];[stack addArrangedSubview:r2];[stack addArrangedSubview:r3];[stack addArrangedSubview:health];'
if old_stack not in s:
    raise SystemExit('home stack marker missing')
s = s.replace(old_stack, new_stack, 1)

old_methods = '- (void)openWorkspace { UIViewController *vc=[[NSClassFromString(@"NKLuaLibraryViewController") alloc]init];vc.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:vc animated:YES]; }\n- (void)openTools { UIViewController *vc=[[NSClassFromString(@"NKLuaToolsViewController") alloc]init];vc.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:vc animated:YES]; }\n- (void)recordInfo {'
new_methods = r'''- (void)openWorkspace { UIViewController *vc=[[NSClassFromString(@"NKLuaLibraryViewController") alloc]init];vc.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:vc animated:YES]; }
- (void)openTools { UIViewController *vc=[[NSClassFromString(@"NKLuaToolsViewController") alloc]init];vc.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:vc animated:YES]; }
- (void)openTaskCenter { NKTaskCenterViewController *vc=[[NKTaskCenterViewController alloc]initWithStyle:UITableViewStyleInsetGrouped];vc.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:vc animated:YES]; }
- (void)runSelfTest {
    UIAlertController *progress=[UIAlertController alertControllerWithTitle:@"Self Test" message:@"Đang kiểm tra Lua → nktask → Logs…" preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))progress.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[self presentViewController:progress animated:YES completion:nil];
    __weak typeof(self)w=self;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSString *name=@"__nk_selftest.lua";NSString *path=NKPath(name);NSString *body=@"local nk=require(\"nktouch_v7\")\nassert(type(nk)==\"table\")\nprint(\"[SELFTEST] lua=ok\")\nprint(\"[SELFTEST] module=ok\")\nprint(\"[SELFTEST] task=ok\")\n";NSError *err=nil;BOOL wrote=[body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
        int cc=99,dc=99,rc=99;NSString *check=wrote?NKLuaRun(@[@"check",name],&cc):@"write failed";NSString *doctor=NKLuaRun(@[@"doctor"],&dc);NSString *start=wrote&&cc==0?NKLuaRun(@[@"run",name],&rc):@"not started";NSString *task=NKParseKV(start)[@"task_id"];NSDictionary *final=@{};NSString *logs=@"";
        if(rc==0&&task.length){for(int i=0;i<50;i++){usleep(100000);int sc=0;NSString *st=NKLuaRun(@[@"status",task],&sc);final=NKParseKV(st);NSString *state=final[@"state"]?:@"";if(!NKTaskStateIsActive(state))break;}int lc=0;logs=NKLuaRun(@[@"logs",task,@"100"],&lc);}
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];NSString *state=final[@"state"]?:@"unknown";BOOL pass=wrote&&cc==0&&dc==0&&rc==0&&[state isEqualToString:@"success"]&&[logs containsString:@"[SELFTEST] task=ok"];
        NSString *summary=[NSString stringWithFormat:@"%@\n\nLua syntax: %@\nTask doctor: %@\nTask run: %@\nFinal state: %@\nLogs: %@",pass?@"✅ PASS":@"❌ FAIL",cc==0?@"OK":@"FAIL",dc==0?@"OK":@"FAIL",rc==0?@"OK":@"FAIL",state,[logs containsString:@"[SELFTEST] task=ok"]?@"OK":@"FAIL"];
        if(!pass){NSString *detail=[NSString stringWithFormat:@"\n\nCheck: %@\nDoctor: %@\nStart: %@\nLogs: %@",check?:@"",doctor?:@"",start?:@"",logs?:@""];summary=[summary stringByAppendingString:detail];}
        dispatch_async(dispatch_get_main_queue(),^{typeof(self)self=w;if(!self)return;[self dismissViewControllerAnimated:YES completion:^{UIAlertController *a=[UIAlertController alertControllerWithTitle:(pass?@"Self Test hoàn tất":@"Self Test phát hiện lỗi") message:summary preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}];});
    });
}
- (void)recordInfo {'''
if old_methods not in s:
    raise SystemExit('dashboard action marker missing')
s = s.replace(old_methods, new_methods, 1)

# Editor/log QoL: auto-scroll freshly loaded logs and expose a copy action while
# on the Logs segment. Saving/checking semantics stay unchanged.
old_mode = '- (void)modeChanged{self.editor.hidden=self.mode.selectedSegmentIndex!=0;'
new_mode = '- (void)modeChanged{self.navigationItem.rightBarButtonItem=(self.mode.selectedSegmentIndex==1?[[UIBarButtonItem alloc]initWithTitle:@"Copy Log" style:UIBarButtonItemStylePlain target:self action:@selector(copyCurrentLog)]:nil);self.editor.hidden=self.mode.selectedSegmentIndex!=0;'
if old_mode not in s:
    raise SystemExit('modeChanged marker missing')
s = s.replace(old_mode, new_mode, 1)
old_logs = '- (void)logsTapped{__weak typeof(self)w=self;NSMutableArray*args=[NSMutableArray arrayWithObject:@"logs"];if(self.taskID.length){[args addObject:self.taskID];[args addObject:@"100"];}[self command:args state:@"Đang tải logs…" done:^(int c,NSString *o){if(c!=0){w.console.text=@"[NKTouch] Chưa có tác vụ hoặc log để hiển thị.";w.runState.text=@"Log chưa sẵn sàng";w.runState.textColor=NKMuted();} else {w.console.text=o;[w pollTaskStatus];}}];}'
new_logs = '- (void)copyCurrentLog{[UIPasteboard generalPasteboard].string=self.console.text?:@"";}\n- (void)logsTapped{__weak typeof(self)w=self;NSMutableArray*args=[NSMutableArray arrayWithObject:@"logs"];if(self.taskID.length){[args addObject:self.taskID];[args addObject:@"100"];}[self command:args state:@"Đang tải logs…" done:^(int c,NSString *o){if(c!=0){w.console.text=@"[NKTouch] Chưa có tác vụ hoặc log để hiển thị.";w.runState.text=@"Log chưa sẵn sàng";w.runState.textColor=NKMuted();} else {w.console.text=o;if(o.length)[w.console scrollRangeToVisible:NSMakeRange(o.length-1,1)];[w pollTaskStatus];}}];}'
if old_logs not in s:
    raise SystemExit('logsTapped marker missing')
s = s.replace(old_logs, new_logs, 1)

settings.write_text(s)

for required in (
    'V7.4.7 daily driver',
    '@"Task Center"',
    '@"Self Test"',
    'NKTaskCenterViewController',
    'NKTaskDetailViewController',
    '@[@"list"]',
    '@[@"doctor"]',
    '[SELFTEST] task=ok',
    'copyCurrentLog',
):
    if required not in s:
        raise SystemExit(f'missing V7.4.7 marker: {required}')

print('Applied NKTouch v0.7.4.7 Daily Driver UX')
