#!/usr/bin/env python3
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v0752-recorder-v3.py <upstream-dir>")

root = Path(sys.argv[1])
settings = root / "zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if not settings.exists():
    raise SystemExit("missing SettingsPageViewController.m")

s = settings.read_text()
if "V0.7.5.2 Recorder V3" in s:
    print("Recorder V3 UI already applied")
    raise SystemExit(0)

anchor = '// V7.4.7 daily driver: Self Test + Task Center + editor/log quality-of-life.\n'
marker = '// V0.7.5.2 Recorder V3: native record/pause/resume/timeline editor/test/render UI.\n'
if anchor in s:
    s = s.replace(anchor, anchor + marker, 1)
else:
    s = marker + s

s = s.replace('NKTouch 0.7.4.7', 'NKTouch 0.7.5.2')
s = s.replace('nkLabel:@"7.4.7"', 'nkLabel:@"0.7.5.2"')
s = s.replace('text:@"7.4.7"', 'text:@"0.7.5.2"')
s = s.replace('title:@"Recorder" subtitle:@"Ghi thao tác"', 'title:@"Recorder V3" subtitle:@"Record • Pause • Timeline"')

forward_old = '@class NKLuaLibraryViewController, NKLuaToolsViewController, NKAIPromptViewController, NKTaskCenterViewController, NKTaskDetailViewController;'
forward_new = '@class NKLuaLibraryViewController, NKLuaToolsViewController, NKAIPromptViewController, NKTaskCenterViewController, NKTaskDetailViewController, NKRecorderV3ViewController;'
if forward_old not in s:
    raise SystemExit('forward class marker missing')
s = s.replace(forward_old, forward_new, 1)

recorder_block = r'''
#pragma mark - Recorder V3
static NSString * const NKRecorderV3Tool = @"/var/jb/usr/bin/nkrecorder";

static NSString *NKRecorderV3Run(NSArray<NSString *> *arguments, int *exitCode) {
    NSArray<NSString *> *args = arguments ?: @[];
    int p[2] = {-1,-1};
    if (pipe(p) != 0) { if(exitCode)*exitCode=126; return @"Không tạo được pipe Recorder."; }
    posix_spawn_file_actions_t a; posix_spawn_file_actions_init(&a);
    posix_spawn_file_actions_adddup2(&a,p[1],STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&a,p[1],STDERR_FILENO);
    posix_spawn_file_actions_addclose(&a,p[0]); posix_spawn_file_actions_addclose(&a,p[1]);
    char **argv=calloc(args.count+2,sizeof(char*)); argv[0]=strdup(NKRecorderV3Tool.UTF8String);
    for(NSUInteger i=0;i<args.count;i++)argv[i+1]=strdup(args[i].UTF8String);argv[args.count+1]=NULL;
    pid_t pid=0;int spawn=posix_spawn(&pid,NKRecorderV3Tool.UTF8String,&a,NULL,argv,environ);
    posix_spawn_file_actions_destroy(&a);close(p[1]);for(NSUInteger i=0;i<args.count+1;i++)free(argv[i]);free(argv);
    if(spawn!=0){close(p[0]);if(exitCode)*exitCode=spawn;return[NSString stringWithFormat:@"Không chạy được nkrecorder (%d).",spawn];}
    NSMutableData *data=[NSMutableData data];uint8_t buf[4096];ssize_t n=0;
    while((n=read(p[0],buf,sizeof(buf)))>0){[data appendBytes:buf length:(NSUInteger)n];if(data.length>524288)break;}close(p[0]);
    int status=0;waitpid(pid,&status,0);int code=WIFEXITED(status)?WEXITSTATUS(status):125;if(exitCode)*exitCode=code;
    NSString *text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];return text.length?text:(code==0?@"OK":[NSString stringWithFormat:@"Recorder lỗi (%d).",code]);
}

static NSArray<NSDictionary*> *NKRecorderV3ParseTimeline(NSString *text) {
    NSMutableArray *rows=[NSMutableArray array];
    [text enumerateLinesUsingBlock:^(NSString *line,BOOL *stop){(void)stop;if(!line.length||[line hasPrefix:@"index\t"])return;NSArray *p=[line componentsSeparatedByString:@"\t"];if(p.count<10)return;[rows addObject:@{@"index":p[0],@"action":p[1],@"idle":p[2],@"duration":p[3],@"x1":p[4],@"y1":p[5],@"x2":p[6],@"y2":p[7],@"finger":p[8],@"points":p[9]}];}];
    return rows;
}

@interface NKRecorderV3ViewController : UIViewController <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong)UILabel *stateLabel;
@property(nonatomic,strong)UILabel *detailLabel;
@property(nonatomic,strong)UITableView *table;
@property(nonatomic,strong)UIButton *recordButton;
@property(nonatomic,strong)UIButton *pauseButton;
@property(nonatomic,strong)UIButton *stopButton;
@property(nonatomic,strong)UIButton *testButton;
@property(nonatomic,strong)UIButton *convertButton;
@property(nonatomic,strong)NSArray<NSDictionary*> *actions;
@property(nonatomic,copy)NSString *timelinePath;
@property(nonatomic,copy)NSString *recState;
@property(nonatomic,strong)NSTimer *statusTimer;
@end

@implementation NKRecorderV3ViewController
- (UIButton*)nkRecorderButton:(NSString*)title tint:(UIColor*)tint action:(SEL)action{
    UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];b.translatesAutoresizingMaskIntoConstraints=NO;[b setTitle:title forState:UIControlStateNormal];[b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightBold];b.backgroundColor=[tint colorWithAlphaComponent:.20];b.layer.cornerRadius=11;b.layer.borderWidth=1;b.layer.borderColor=[tint colorWithAlphaComponent:.55].CGColor;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;
}
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"Recorder V3";self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;self.view.backgroundColor=NKBG();if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UIView *head=[[UIView alloc]init];head.translatesAutoresizingMaskIntoConstraints=NO;NKCard(head,15);
    UILabel *title=[[UILabel alloc]init];title.translatesAutoresizingMaskIntoConstraints=NO;title.text=@"Ghi thao tác thật";title.textColor=UIColor.whiteColor;title.font=[UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    self.stateLabel=[[UILabel alloc]init];self.stateLabel.translatesAutoresizingMaskIntoConstraints=NO;self.stateLabel.text=@"● Đang tải";self.stateLabel.textColor=NKBlue();self.stateLabel.font=[UIFont systemFontOfSize:12.5 weight:UIFontWeightBold];
    self.detailLabel=[[UILabel alloc]init];self.detailLabel.translatesAutoresizingMaskIntoConstraints=NO;self.detailLabel.text=@"Tap / Hold / Swipe + timing";self.detailLabel.textColor=NKMuted();self.detailLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    [head addSubview:title];[head addSubview:self.stateLabel];[head addSubview:self.detailLabel];
    self.recordButton=[self nkRecorderButton:@"● Record" tint:NKRed() action:@selector(recordTapped)];
    self.pauseButton=[self nkRecorderButton:@"Ⅱ Pause" tint:NKC(0xFFB545) action:@selector(pauseResumeTapped)];
    self.stopButton=[self nkRecorderButton:@"■ Stop" tint:NKMuted() action:@selector(stopTapped)];
    UIStackView *controls=[[UIStackView alloc]initWithArrangedSubviews:@[self.recordButton,self.pauseButton,self.stopButton]];controls.translatesAutoresizingMaskIntoConstraints=NO;controls.axis=UILayoutConstraintAxisHorizontal;controls.spacing=8;controls.distribution=UIStackViewDistributionFillEqually;
    UILabel *timelineTitle=[[UILabel alloc]init];timelineTitle.translatesAutoresizingMaskIntoConstraints=NO;timelineTitle.text=@"TIMELINE";timelineTitle.textColor=NKMuted();timelineTitle.font=[UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    self.table=[[UITableView alloc]initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];self.table.translatesAutoresizingMaskIntoConstraints=NO;self.table.backgroundColor=NKBG();self.table.separatorColor=NKBorder();self.table.dataSource=self;self.table.delegate=self;
    self.testButton=[self nkRecorderButton:@"▶ Test lại" tint:NKBlue() action:@selector(testTapped)];
    self.convertButton=[self nkRecorderButton:@"Convert → Lua" tint:NKGreen() action:@selector(convertTapped)];
    UIStackView *bottom=[[UIStackView alloc]initWithArrangedSubviews:@[self.testButton,self.convertButton]];bottom.translatesAutoresizingMaskIntoConstraints=NO;bottom.axis=UILayoutConstraintAxisHorizontal;bottom.spacing=10;bottom.distribution=UIStackViewDistributionFillEqually;
    [self.view addSubview:head];[self.view addSubview:controls];[self.view addSubview:timelineTitle];[self.view addSubview:self.table];[self.view addSubview:bottom];UILayoutGuide*safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[head.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],[head.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],[head.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],[head.heightAnchor constraintEqualToConstant:88],[title.leadingAnchor constraintEqualToAnchor:head.leadingAnchor constant:14],[title.topAnchor constraintEqualToAnchor:head.topAnchor constant:12],[self.stateLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[self.stateLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:7],[self.detailLabel.trailingAnchor constraintEqualToAnchor:head.trailingAnchor constant:-14],[self.detailLabel.centerYAnchor constraintEqualToAnchor:self.stateLabel.centerYAnchor],[controls.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:10],[controls.leadingAnchor constraintEqualToAnchor:head.leadingAnchor],[controls.trailingAnchor constraintEqualToAnchor:head.trailingAnchor],[controls.heightAnchor constraintEqualToConstant:42],[timelineTitle.topAnchor constraintEqualToAnchor:controls.bottomAnchor constant:13],[timelineTitle.leadingAnchor constraintEqualToAnchor:head.leadingAnchor constant:3],[bottom.leadingAnchor constraintEqualToAnchor:head.leadingAnchor],[bottom.trailingAnchor constraintEqualToAnchor:head.trailingAnchor],[bottom.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],[bottom.heightAnchor constraintEqualToConstant:42],[self.table.topAnchor constraintEqualToAnchor:timelineTitle.bottomAnchor constant:4],[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.table.bottomAnchor constraintEqualToAnchor:bottom.topAnchor constant:-6]]];
    self.actions=@[];[self refreshStatus];[self loadLatest];self.statusTimer=[NSTimer scheduledTimerWithTimeInterval:.8 target:self selector:@selector(refreshStatus) userInfo:nil repeats:YES];[[NSRunLoop mainRunLoop]addTimer:self.statusTimer forMode:NSRunLoopCommonModes];
}
- (void)viewWillDisappear:(BOOL)animated{[self.statusTimer invalidate];self.statusTimer=nil;[super viewWillDisappear:animated];}
- (void)run:(NSArray<NSString*>*)args done:(void(^)(int,NSString*))done{dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{int c=0;NSString*o=NKRecorderV3Run(args,&c);dispatch_async(dispatch_get_main_queue(),^{if(done)done(c,o?:@"");});});}
- (void)refreshStatus{__weak typeof(self)w=self;[self run:@[@"status"] done:^(int c,NSString*o){typeof(self)self=w;if(!self||c!=0)return;NSDictionary*d=NKParseKV(o);NSString*state=d[@"state"]?:@"idle";self.recState=state;NSInteger segments=[d[@"segments"] integerValue];if([state isEqualToString:@"recording"]){self.stateLabel.text=@"● ĐANG GHI";self.stateLabel.textColor=NKRed();self.pauseButton.enabled=YES;[self.pauseButton setTitle:@"Ⅱ Pause" forState:UIControlStateNormal];self.recordButton.enabled=NO;self.stopButton.enabled=YES;}else if([state isEqualToString:@"paused"]){self.stateLabel.text=@"Ⅱ ĐÃ TẠM DỪNG";self.stateLabel.textColor=NKC(0xFFB545);self.pauseButton.enabled=YES;[self.pauseButton setTitle:@"▶ Resume" forState:UIControlStateNormal];self.recordButton.enabled=NO;self.stopButton.enabled=YES;}else{self.stateLabel.text=@"● SẴN SÀNG";self.stateLabel.textColor=NKGreen();self.pauseButton.enabled=NO;[self.pauseButton setTitle:@"Ⅱ Pause" forState:UIControlStateNormal];self.recordButton.enabled=YES;self.stopButton.enabled=NO;}self.recordButton.alpha=self.recordButton.enabled?1:.35;self.pauseButton.alpha=self.pauseButton.enabled?1:.35;self.stopButton.alpha=self.stopButton.enabled?1:.35;self.detailLabel.text=[NSString stringWithFormat:@"%ld segment • Tap / Hold / Swipe",(long)segments];}];}
- (void)recordTapped{__weak typeof(self)w=self;[self run:@[@"start"] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;[self refreshStatus];if(c==0){UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Recorder đang chạy" message:@"Chuyển sang app cần ghi. Khi cần nghỉ, quay lại NKTouch và bấm Pause." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}else [self showRecorderError:o];}];}
- (void)pauseResumeTapped{NSString*cmd=[self.recState isEqualToString:@"paused"]?@"resume":@"pause";__weak typeof(self)w=self;[self run:@[cmd] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;if(c!=0)[self showRecorderError:o];[self refreshStatus];}];}
- (void)stopTapped{UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Dừng và tạo Timeline" message:@"Đặt tên hoặc để trống để dùng tên tự động." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"login-flow";f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];__weak typeof(self)w=self;[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Tạo Timeline" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;typeof(self)self=w;if(!self)return;NSString*n=a.textFields.firstObject.text?:@"";NSMutableArray*args=[NSMutableArray arrayWithObject:@"stop"];if(n.length)[args addObject:n];[self run:args done:^(int c,NSString*o){if(c!=0){[self showRecorderError:o];return;}self.timelinePath=NKParseKV(o)[@"timeline"];[self refreshStatus];[self reloadTimeline];}];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)showRecorderError:(NSString*)message{UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Recorder V3" message:(message.length?message:@"Có lỗi xảy ra.") preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)loadLatest{__weak typeof(self)w=self;[self run:@[@"latest"] done:^(int c,NSString*o){typeof(self)self=w;if(!self||c!=0)return;self.timelinePath=[o stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];[self reloadTimeline];}];}
- (void)reloadTimeline{if(!self.timelinePath.length){self.actions=@[];[self.table reloadData];self.testButton.enabled=NO;self.convertButton.enabled=NO;self.testButton.alpha=.35;self.convertButton.alpha=.35;return;}NSString*p=self.timelinePath;__weak typeof(self)w=self;[self run:@[@"inspect",p] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;if(c==0){self.actions=NKRecorderV3ParseTimeline(o);[self.table reloadData];BOOL ready=self.actions.count>0;self.testButton.enabled=ready;self.convertButton.enabled=ready;self.testButton.alpha=ready?1:.35;self.convertButton.alpha=ready?1:.35;}else [self showRecorderError:o];}];}
- (NSInteger)tableView:(UITableView*)tv numberOfRowsInSection:(NSInteger)section{(void)tv;(void)section;return MAX((NSInteger)self.actions.count,1);}
- (UITableViewCell*)tableView:(UITableView*)tv cellForRowAtIndexPath:(NSIndexPath*)ip{UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:@"recAction"];if(!c)c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"recAction"];c.backgroundColor=NKPanel();c.textLabel.textColor=UIColor.whiteColor;c.detailTextLabel.textColor=NKMuted();if(!self.actions.count){c.textLabel.text=@"Chưa có Timeline";c.detailTextLabel.text=@"Bấm Record để ghi thao tác thật.";c.imageView.image=NKIcon(@"record.circle",18);c.imageView.tintColor=NKMuted();c.accessoryType=UITableViewCellAccessoryNone;return c;}NSDictionary*d=self.actions[ip.row];NSString*a=[d[@"action"] uppercaseString];NSString*xy=[d[@"action"] isEqualToString:@"swipe"]?[NSString stringWithFormat:@"(%@,%@) → (%@,%@)",d[@"x1"],d[@"y1"],d[@"x2"],d[@"y2"]]:[NSString stringWithFormat:@"(%@,%@)",d[@"x1"],d[@"y1"]];c.textLabel.text=[NSString stringWithFormat:@"#%@  %@  %@",d[@"index"],a,xy];c.detailTextLabel.text=[NSString stringWithFormat:@"delay %@ ms • duration %@ ms",d[@"idle"],d[@"duration"]];c.imageView.image=NKIcon([d[@"action"] isEqualToString:@"swipe"]?@"arrow.up.right":([d[@"action"] isEqualToString:@"hold"]?@"hand.point.up.left.fill":@"dot.circle.fill"),18);c.imageView.tintColor=NKPurple();c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{[tv deselectRowAtIndexPath:ip animated:YES];if(ip.row>=self.actions.count)return;[self showEditMenu:ip.row];}
- (void)showEditMenu:(NSInteger)row{NSDictionary*d=self.actions[row];UIAlertController*a=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Action #%@",d[@"index"]] message:@"Chỉnh Timeline trước khi Test hoặc Convert." preferredStyle:UIAlertControllerStyleActionSheet];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;__weak typeof(self)w=self;[a addAction:[UIAlertAction actionWithTitle:@"Đổi loại Tap / Hold / Swipe" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w chooseTypeAt:row];}]],[a addAction:[UIAlertAction actionWithTitle:@"Sửa thời gian" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w editTimingAt:row];}]],[a addAction:[UIAlertAction actionWithTitle:@"Sửa tọa độ" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w editCoordsAt:row];}]],[a addAction:[UIAlertAction actionWithTitle:@"Đưa lên" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w moveRow:row delta:-1];}]],[a addAction:[UIAlertAction actionWithTitle:@"Đưa xuống" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w moveRow:row delta:1];}]],[a addAction:[UIAlertAction actionWithTitle:@"Xóa action" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*x){(void)x;[w deleteRow:row];}]],[a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)applyEditAt:(NSInteger)row fields:(NSArray<NSString*>*)fields{if(row>=self.actions.count||!self.timelinePath.length)return;NSString*idx=self.actions[row][@"index"];NSMutableArray*args=[NSMutableArray arrayWithObjects:@"edit",self.timelinePath,idx,nil];[args addObjectsFromArray:fields];__weak typeof(self)w=self;[self run:args done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;if(c==0)[self reloadTimeline];else[self showRecorderError:o];}];}
- (void)chooseTypeAt:(NSInteger)row{UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Loại action" message:nil preferredStyle:UIAlertControllerStyleActionSheet];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;__weak typeof(self)w=self;for(NSString*t in @[@"tap",@"hold",@"swipe"]){[a addAction:[UIAlertAction actionWithTitle:t.uppercaseString style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w applyEditAt:row fields:@[[NSString stringWithFormat:@"action=%@",t]]];}]];}[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)editTimingAt:(NSInteger)row{NSDictionary*d=self.actions[row];UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Thời gian" message:@"Delay = thời gian chờ trước action." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"Delay ms";f.keyboardType=UIKeyboardTypeNumberPad;f.text=d[@"idle"];}];[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"Duration ms";f.keyboardType=UIKeyboardTypeNumberPad;f.text=d[@"duration"];}];__weak typeof(self)w=self;[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w applyEditAt:row fields:@[[NSString stringWithFormat:@"idle_ms=%@",a.textFields[0].text?:@"0"],[NSString stringWithFormat:@"duration_ms=%@",a.textFields[1].text?:@"1"]]];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)editCoordsAt:(NSInteger)row{NSDictionary*d=self.actions[row];UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Tọa độ" message:@"x2/y2 chỉ dùng cho Swipe." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;NSArray*keys=@[@"x1",@"y1",@"x2",@"y2"];for(NSString*k in keys){[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=k;f.keyboardType=UIKeyboardTypeDecimalPad;f.text=d[k];}];}__weak typeof(self)w=self;[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;NSMutableArray*f=[NSMutableArray array];for(NSUInteger i=0;i<keys.count;i++)[f addObject:[NSString stringWithFormat:@"%@=%@",keys[i],a.textFields[i].text?:@"0"]];[w applyEditAt:row fields:f];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)deleteRow:(NSInteger)row{if(row>=self.actions.count)return;NSString*idx=self.actions[row][@"index"];__weak typeof(self)w=self;[self run:@[@"delete",self.timelinePath,idx] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;if(c==0)[self reloadTimeline];else[self showRecorderError:o];}];}
- (void)moveRow:(NSInteger)row delta:(NSInteger)delta{NSInteger target=row+delta;if(row>=self.actions.count||target<0||target>=self.actions.count)return;NSString*from=self.actions[row][@"index"];NSString*to=self.actions[target][@"index"];__weak typeof(self)w=self;[self run:@[@"move",self.timelinePath,from,to] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;if(c==0)[self reloadTimeline];else[self showRecorderError:o];}];}
- (void)testTapped{if(!self.timelinePath.length)return;__weak typeof(self)w=self;[self run:@[@"test",self.timelinePath] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;if(c!=0){[self showRecorderError:o];return;}NSString*task=NKParseKV(o)[@"task_id"];if(task.length){NKTaskDetailViewController*vc=[[NKTaskDetailViewController alloc]initWithTaskID:task];vc.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:vc animated:YES];}else{UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Đã chạy Test" message:o preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}}];}
- (void)convertTapped{if(!self.timelinePath.length)return;NSString*def=[[self.timelinePath lastPathComponent]stringByDeletingPathExtension];UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Convert → Lua" message:@"Script sẽ được lưu thẳng vào thư viện NKTouch." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.text=def;f.placeholder=@"recorded-flow.lua";f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];__weak typeof(self)w=self;[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Tạo Lua" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;typeof(self)self=w;if(!self)return;NSString*n=a.textFields.firstObject.text?:def;[self run:@[@"render",self.timelinePath,n] done:^(int c,NSString*o){if(c!=0){[self showRecorderError:o];return;}NSString*path=NKParseKV(o)[@"script"];NSString*name=path.lastPathComponent;if(!name.length){[self showRecorderError:o];return;}Class cls=NSClassFromString(@"NKLuaEditorViewController");UIViewController*editor=[[cls alloc]init];[editor setValue:name forKey:@"scriptName"];editor.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:editor animated:YES];}];}]];[self presentViewController:a animated:YES completion:nil];}
@end

'''

dashboard_marker = '#pragma mark - Dashboard\n'
if dashboard_marker not in s:
    raise SystemExit('dashboard marker missing')
s = s.replace(dashboard_marker, recorder_block + dashboard_marker, 1)

record_pattern = re.compile(r'- \(void\)recordInfo \{.*?\}\n@end', re.S)
record_new = '- (void)recordInfo { NKRecorderV3ViewController *vc=[[NKRecorderV3ViewController alloc]init];vc.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:vc animated:YES]; }\n@end'
s, n = record_pattern.subn(record_new, s, count=1)
if n != 1:
    raise SystemExit(f'recordInfo replacement failed: {n}')

settings.write_text(s)
for required in (
    'V0.7.5.2 Recorder V3',
    'NKRecorderV3ViewController',
    'Record • Pause • Timeline',
    '@"pause"',
    '@"resume"',
    '@"inspect"',
    '@"edit"',
    '@"move"',
    '@"delete"',
    '@"test"',
    '@"render"',
    'Convert → Lua',
):
    if required not in s:
        raise SystemExit(f'missing Recorder V3 marker: {required}')

print('Applied NKTouch 0.7.5.2 Recorder V3 native UI')
