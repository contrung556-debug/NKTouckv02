// NKTouch v0.7.16-dev Test Lab UI
// Reuses the existing Lua Editor / target-app picker / task supervisor.
// NO direct touch/keyboard/network action is initiated from this controller.
#pragma mark - NKTouch Test Lab
@interface NKLuaTestLabViewController : UIViewController <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) NSMutableSet<NSString*> *chosen;
@property(nonatomic,strong) UILabel *summary;
@property(nonatomic,strong) UILabel *hint;
@property(nonatomic,copy) NSString *reportCopyPayload;
@end

@implementation NKLuaTestLabViewController

- (NSArray<NSDictionary *> *)labGroups {
    static NSArray<NSDictionary *> *items;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        items=@[
            @{@"id":@"ocr",     @"title":@"OCR Engine", @"desc":@"Ảnh dùng lại • OCR native • OCR trực tiếp"},
            @{@"id":@"color",   @"title":@"Color Engine", @"desc":@"RGB • sai số • tìm màu 1 pixel"},
            @{@"id":@"touch",   @"title":@"Touch Engine", @"desc":@"Tọa độ • tap/hold/swipe an toàn"},
            @{@"id":@"input",   @"title":@"InputText", @"desc":@"Input Engine • Unicode • gửi một lần"},
            @{@"id":@"memory",  @"title":@"Memory Stability", @"desc":@"10 frame • RSS • giải phóng Lua"},
            @{@"id":@"diagnostics", @"title":@"Diagnostics & Crash", @"desc":@"Lệnh cuối • exit_code • signal • bảo vệ log"},
            @{@"id":@"runtime", @"title":@"Lua Runtime", @"desc":@"Lua 5.4 • module • cú pháp"},
            @{@"id":@"vision",  @"title":@"Vision Core", @"desc":@"Frame • pixel • ảnh mẫu"},
            @{@"id":@"network", @"title":@"Network & JSON", @"desc":@"JSON • URL • HTTPS có xác nhận"},
            @{@"id":@"task",    @"title":@"Task Stability", @"desc":@"IPC • timeout • stress nhẹ"}
        ];
    });
    return items;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"NKTouch Test Lab";
    self.view.backgroundColor=NKBG();
    if (@available(iOS 13.0,*)) self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.chosen=[NSMutableSet set];
    [self.chosen addObjectsFromArray:@[@"ocr",@"color",@"touch",@"input",@"memory"]];

    UIBarButtonItem *reportButton=[[UIBarButtonItem alloc]
        initWithTitle:@"Báo cáo" style:UIBarButtonItemStylePlain
        target:self action:@selector(labShowReport)];
    UIBarButtonItem *presetButton=[[UIBarButtonItem alloc]
        initWithTitle:@"5 lõi" style:UIBarButtonItemStylePlain
        target:self action:@selector(labSelectCorePreset)];
    self.navigationItem.rightBarButtonItems=@[reportButton,presetButton];

    UILabel *title=[[UILabel alloc]init];
    title.translatesAutoresizingMaskIntoConstraints=NO;
    title.text=@"Kiểm tra 5 chức năng cốt lõi";
    title.font=[UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    title.textColor=UIColor.whiteColor;

    self.hint=[[UILabel alloc]init];
    self.hint.translatesAutoresizingMaskIntoConstraints=NO;
    self.hint.text=@"Mặc định chọn OCR, Color, Touch, InputText, Memory. Chỉ đọc; thử chạm/nhập cần bật và xác nhận trong Lua Editor. Chọn thêm nhóm nâng cao khi cần.";
    self.hint.numberOfLines=0;
    self.hint.font=[UIFont systemFontOfSize:12];
    self.hint.textColor=NKMuted();

    self.table=[[UITableView alloc]initWithFrame:CGRectZero
                                               style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints=NO;
    self.table.backgroundColor=UIColor.clearColor;
    self.table.rowHeight=64;
    self.table.dataSource=self;
    self.table.delegate=self;
    self.table.allowsMultipleSelection=NO;

    UIButton *create=[UIButton buttonWithType:UIButtonTypeSystem];
    create.translatesAutoresizingMaskIntoConstraints=NO;
    [create setTitle:@"Tạo bài kiểm tra → Lua Editor" forState:UIControlStateNormal];
    create.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    create.backgroundColor=NKPurple();
    create.tintColor=UIColor.whiteColor;
    create.layer.cornerRadius=12;
    [create addTarget:self action:@selector(labCreateRunner)
          forControlEvents:UIControlEventTouchUpInside];

    self.summary=[[UILabel alloc]init];
    self.summary.translatesAutoresizingMaskIntoConstraints=NO;
    self.summary.numberOfLines=2;
    self.summary.textAlignment=NSTextAlignmentCenter;
    self.summary.textColor=NKMuted();
    self.summary.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
    self.summary.text=@"Chưa có báo cáo Test Lab";

    [self.view addSubview:title];
    [self.view addSubview:self.hint];
    [self.view addSubview:self.table];
    [self.view addSubview:create];
    [self.view addSubview:self.summary];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [title.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [self.hint.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.hint.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.table.topAnchor constraintEqualToAnchor:self.hint.bottomAnchor constant:8],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:create.topAnchor constant:-8],
        [create.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [create.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [create.heightAnchor constraintEqualToConstant:48],
        [self.summary.topAnchor constraintEqualToAnchor:create.bottomAnchor constant:8],
        [self.summary.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.summary.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.summary.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [self.summary.heightAnchor constraintGreaterThanOrEqualToConstant:32]
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self labRefreshSummary];
    [self.table reloadData];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; (void)section;
    return [self labGroups].count;
}

- (UITableViewCell *)tableView:(UITableView *)table
        cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const key=@"NKLabGroup";
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:key];
    if (!cell) cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:key];
    NSDictionary *group=[self labGroups][(NSUInteger)indexPath.row];
    cell.textLabel.text=group[@"title"];
    cell.textLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    cell.textLabel.textColor=UIColor.whiteColor;
    NSDictionary *lastReport=[self labReadReport];
    NSDictionary *prevGroups=[lastReport[@"groups"] isKindOfClass:[NSDictionary class]]?
       lastReport[@"groups"]:@{};
    NSDictionary *prior=[prevGroups[group[@"id"]] isKindOfClass:[NSDictionary class]]?
       prevGroups[group[@"id"]]:nil;
    NSString *priorStatus=[prior[@"status"] isKindOfClass:[NSString class]]?
       prior[@"status"]:nil;
    cell.detailTextLabel.text=priorStatus?
       [NSString stringWithFormat:@"%@ • lần trước: %@",group[@"desc"],priorStatus]:
       group[@"desc"];
    cell.detailTextLabel.textColor=[priorStatus isEqualToString:@"FAIL"]?
         NKC(0xFF7777):([priorStatus isEqualToString:@"PASS"]?NKGreen():NKMuted());
    cell.detailTextLabel.font=[UIFont systemFontOfSize:11];
    cell.backgroundColor=NKC(0x202139);
    cell.accessoryType=[self.chosen containsObject:group[@"id"]]?
       UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    cell.tintColor=NKGreen();
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [table deselectRowAtIndexPath:ip animated:YES];
    NSString *key=[self labGroups][(NSUInteger)ip.row][@"id"];
    if ([self.chosen containsObject:key]) [self.chosen removeObject:key];
    else [self.chosen addObject:key];
    [table reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)labSelectCorePreset {
    [self.chosen removeAllObjects];
    [self.chosen addObjectsFromArray:@[@"ocr",@"color",@"touch",@"input",@"memory"]];
    [self.table reloadData];
}

- (void)labAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title
              message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng"
                  style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)labReportPath {
    return @"/var/mobile/Library/NKTouch/tmp/testlab-last.json";
}

- (NSDictionary *)labReadReport {
    NSData *raw=[NSData dataWithContentsOfFile:[self labReportPath]];
    if (!raw || raw.length>256*1024) return nil;
    id value=[NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
    if (![value isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *report=(NSDictionary *)value;
    if (![report[@"version"] isKindOfClass:[NSString class]] ||
        ![report[@"tests"] isKindOfClass:[NSArray class]]) return nil;
    return report;
}

- (void)labRefreshSummary {
    NSDictionary *report=[self labReadReport];
    if (!report) {
        self.summary.text=@"Chưa có báo cáo · Xem Task Center để đọc log";
        return;
    }
    self.summary.text=[NSString stringWithFormat:
      @"Báo cáo gần nhất: %@ (%@)\nPASS %@  FAIL %@  WARN %@  SKIP %@",
      report[@"status"]?:@"—",report[@"coverage"]?:@"PARTIAL",
      report[@"pass"]?:@0,report[@"fail"]?:@0,
      report[@"warn"]?:@0,report[@"skip"]?:@0];
}

- (NSString *)labReportText:(NSDictionary *)report {
    NSMutableString *out=[NSMutableString stringWithFormat:
        @"NKTouch Test Lab\nRun: %@\nVersion: %@\nStatus: %@\nPASS %@ | FAIL %@ | WARN %@ | SKIP %@\n\n",
        report[@"run_id"]?:@"-",report[@"version"]?:@"-",
        report[@"status"]?:@"-",report[@"pass"]?:@0,report[@"fail"]?:@0,
        report[@"warn"]?:@0,report[@"skip"]?:@0];
    NSDictionary *timing=[report[@"timing"] isKindOfClass:[NSDictionary class]]?
         report[@"timing"]:@{};
    [out appendFormat:@"Coverage: %@ | Mode: %@ | Visual confirmation: %@\n",
         report[@"coverage"]?:@"UNKNOWN",report[@"mode"]?:@"UNKNOWN",
         [report[@"visual_confirmation"] boolValue]?@"YES":@"NO"];
    [out appendFormat:@"Timing source: %@ (CPU time is not wall time)\n",
         report[@"clock_type"]?:@"unknown"];
    [out appendFormat:@"Elapsed %@ms | Avg/check %@ms | P95/check %@ms | Max/check %@ms\n",
         timing[@"elapsed_ms"]?:@0,timing[@"avg_check_ms"]?:@0,
         timing[@"p95_check_ms"]?:@0,timing[@"max_check_ms"]?:@0];
    [out appendString:@"NOTE: PASS means completed checks passed, NOT that touches, OCR or text were visually confirmed.\n"];
    [out appendString:@"P95 is over different checks in one run, not per-API long-term latency.\n\n"];
    NSDictionary *groups=[report[@"groups"] isKindOfClass:[NSDictionary class]]?
        report[@"groups"]:@{};
    NSArray *order=@[@"ocr",@"color",@"touch",@"input",@"memory",@"diagnostics",@"runtime",@"vision",@"network",@"task"];
    for (NSString *groupName in order) {
        NSDictionary *g=[groups[groupName] isKindOfClass:[NSDictionary class]]?
             groups[groupName]:nil;
        if (!g) continue;
        NSDictionary *measure=[g[@"timing"] isKindOfClass:[NSDictionary class]]?
             g[@"timing"]:@{};
        [out appendFormat:@"%@: %@ • checks %@ • avg %@ms • p95 %@ms • max %@ms\n",
            g[@"title"]?:groupName,g[@"status"]?:@"?",
            measure[@"checks"]?:@0,measure[@"avg_check_ms"]?:@0,
            measure[@"p95_check_ms"]?:@0,measure[@"max_check_ms"]?:@0];
        if (g[@"check_pass_rate_pct"])
            [out appendFormat:@"  PASS of executed checks: %@%% (not touch accuracy)\n",
                g[@"check_pass_rate_pct"]];
    }
    NSDictionary *comparison=[report[@"regression"] isKindOfClass:[NSDictionary class]]?report[@"regression"]:@{};
    [out appendFormat:@"Previous-run comparison: %@\\n",comparison[@"status"]?:@"NO_BASELINE"];
    NSArray *changes=[comparison[@"regressions"] isKindOfClass:[NSArray class]]?comparison[@"regressions"]:@[];
    for (NSDictionary *change in changes) {
        if ([change isKindOfClass:[NSDictionary class]])
            [out appendFormat:@"REGRESSION %@: %@ -> %@\\n",change[@"check"]?:@"?",change[@"from"]?:@"?",change[@"to"]?:@"?"];
    }
    [out appendString:@"\nPer-check details:\n"];
    NSArray *tests=report[@"tests"];
    NSUInteger count=MIN(tests.count,(NSUInteger)180);
    for (NSUInteger i=0;i<count;i++) {
        NSDictionary *test=[tests[i] isKindOfClass:[NSDictionary class]]?tests[i]:nil;
        if (!test) continue;
        NSString *detail=[test[@"detail"] isKindOfClass:[NSString class]]?
            test[@"detail"]:@"";
        if (detail.length>200) detail=[detail substringToIndex:200];
        [out appendFormat:@"[%@] %@/%@ (%@ms)\n%@\n\n",
          test[@"status"]?:@"-",test[@"group"]?:@"-",test[@"name"]?:@"-",
          test[@"ms"]?:@0,detail];
    }
    return out;
}

- (void)labCopyReport {
    if (self.reportCopyPayload.length) [UIPasteboard generalPasteboard].string=self.reportCopyPayload;
}

- (void)labShowReport {
    NSDictionary *report=[self labReadReport];
    if (!report) {
        [self labAlert:@"Chưa có báo cáo"
               message:@"Chạy bài kiểm tra trong Lua Editor rồi quay lại Test Lab. Log từng bước có trong Task Center."];
        return;
    }
    NSString *details=[self labReportText:report];
    self.reportCopyPayload=details;
    UIViewController *viewer=[[UIViewController alloc]init];
    viewer.title=@"Kết quả Test Lab";
    viewer.view.backgroundColor=NKBG();
    UITextView *text=[[UITextView alloc]init];
    text.translatesAutoresizingMaskIntoConstraints=NO;
    text.editable=NO;
    text.backgroundColor=UIColor.clearColor;
    text.textColor=UIColor.whiteColor;
    text.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    text.text=details;
    [viewer.view addSubview:text];
    UILayoutGuide *safe=viewer.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
      [text.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
      [text.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
      [text.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
      [text.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10]
    ]];
    viewer.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]
       initWithTitle:@"Sao chép" style:UIBarButtonItemStylePlain
       target:self action:@selector(labCopyReport)];
    [self.navigationController pushViewController:viewer animated:YES];
}

- (void)labCreateRunner {
    if (self.chosen.count==0) {
        [self labAlert:@"Chọn ít nhất một nhóm" message:@"Không có bài kiểm tra nào được chọn."];
        return;
    }
    // All identifiers come from hardcoded whitelist, not user input.
    NSMutableArray<NSString *> *quoted=[NSMutableArray array];
    for (NSDictionary *item in [self labGroups]) {
        NSString *key=item[@"id"];
        if ([self.chosen containsObject:key])
            [quoted addObject:[NSString stringWithFormat:@"\"%@\"",key]];
    }
    NSString *uuid=[[[NSUUID UUID].UUIDString
           stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    NSString *shortID=[uuid substringToIndex:12];
    NSString *filename=[NSString stringWithFormat:@"nktestlab_%@.lua",shortID];
    NSString *runID=[NSString stringWithFormat:@"lab_%@",uuid];
    // Each execution gets a unique filename. Never overwrite user-edited Lua.
    NSString *script=[NSString stringWithFormat:
     @"-- NKTouch Test Lab v0.7.19-dev | Generated: %@\n"
      @"-- Default: READ ONLY. Touch / Input / HTTPS will not run without opt-in.\n"
      @"-- For interactions: set enabled=true AND confirmed=true only after\n"
      @"-- setting a safe non-sensitive test screen and physical-pixel coordinates.\n"
      @"-- To enable interactive tests: choose the correct target via 'Ứng dụng +',\n"
      @"-- then edit bundle ID and physical-pixel coordinates below.\n"
      @"local lab=require(\"nktestlab\")\n"
      @"local opts={\n"
      @"  run_id=\"%@\",\n"
      @"  selected={%@},\n"
      @"  touch={enabled=false,confirmed=false,bundle=\"\",tap={x=0,y=0},hold={x=0,y=0,ms=400},\n"
      @"         swipe={x1=0,y1=0,x2=0,y2=0,ms=500}},\n"
      @"  input={enabled=false,confirmed=false,bundle=\"\",x=0,y=0,text=\"NKTouch Lab Test\"},\n"
      @"  network={enabled=false},\n"
      @"  vision={},\n"
      @"  memory={loops=10}\n"
      @"}\n"
      @"local result=lab.run(opts)\n"
      @"if result.fail>0 then error(\"NKTouch Test Lab FAILED; see Task Center Logs\",0) end\n",
      runID,runID,[quoted componentsJoinedByString:@","]];
    // Dashboard can open Test Lab before Lua Library is visited.
    // NKScripts() creates the scripts directory without touching user files.
    (void)NKScripts();
    NSString *path=NKPath(filename);
    NSFileManager *fs=[NSFileManager defaultManager];
    NSError *dirError=nil;
    if (![fs createDirectoryAtPath:@"/var/mobile/Library/NKTouch/tmp"
       withIntermediateDirectories:YES attributes:nil error:&dirError]) {
        [self labAlert:@"Không chuẩn bị được báo cáo"
               message:dirError.localizedDescription?:@"Không tạo được thư mục Test Lab"];
        return;
    }
    if ([fs fileExistsAtPath:path]) {
        [self labAlert:@"Tên script đã tồn tại" message:@"Không ghi đè bản Lua hiện có."];
        return;
    }
    NSError *err=nil;
    if (![script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        [self labAlert:@"Không tạo được script" message:err.localizedDescription?:@"Lỗi ghi file"];
        return;
    }
    if (!NKTargetForScript(filename)) {
        if (!NKSaveTarget(filename,@"com.apple.mobilesafari",@"Safari")) {
            [self labAlert:@"Chưa thiết lập ứng dụng đích"
                   message:@"Script đã được tạo nhưng chưa chọn được Safari. Hãy mở script trong Lua Workspace và chọn ứng dụng bằng 'Ứng dụng +' trước khi chạy."];
            return;
        }
    }
    [self.navigationController pushViewController:
       [[NKLuaEditorViewController alloc]initWithScriptName:filename] animated:YES];
}
@end
