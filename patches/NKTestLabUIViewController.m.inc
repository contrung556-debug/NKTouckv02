// NKTouch v0.7.16-dev Test Lab UI
// Reuses the existing Lua Editor / target-app picker / task supervisor.
// NO direct touch/keyboard/network action is initiated from this controller.
#pragma mark - NKTouch Test Lab
@interface NKLuaTestLabViewController : UIViewController <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) NSMutableSet<NSString*> *chosen;
@property(nonatomic,strong) UILabel *summary;
@property(nonatomic,strong) UILabel *hint;
@property(nonatomic,copy) NSString *copyText;
@end

@implementation NKLuaTestLabViewController

- (NSArray<NSDictionary *> *)labGroups {
    static NSArray<NSDictionary *> *items;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        items=@[
            @{@"id":@"runtime", @"title":@"Lua Runtime", @"desc":@"Lua 5.4 • module • cú pháp"},
            @{@"id":@"touch",   @"title":@"Touch Engine", @"desc":@"Tap • Hold • Swipe • Path"},
            @{@"id":@"input",   @"title":@"Input Engine", @"desc":@"Unicode • kiểm tra an toàn"},
            @{@"id":@"color",   @"title":@"Color Engine", @"desc":@"getColor • matchColor • findColor"},
            @{@"id":@"vision",  @"title":@"Vision Core", @"desc":@"Ảnh dùng lại • OCR • mẫu ảnh"},
            @{@"id":@"network", @"title":@"Network & JSON", @"desc":@"JSON • kiểm tra URL • HTTPS tùy chọn"},
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
    for (NSDictionary *item in [self labGroups]) [self.chosen addObject:item[@"id"]];

    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]
        initWithTitle:@"Báo cáo" style:UIBarButtonItemStylePlain
        target:self action:@selector(labShowReport)];

    UILabel *title=[[UILabel alloc]init];
    title.translatesAutoresizingMaskIntoConstraints=NO;
    title.text=@"Kiểm tra các lệnh hiện có";
    title.font=[UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    title.textColor=UIColor.whiteColor;

    self.hint=[[UILabel alloc]init];
    self.hint.translatesAutoresizingMaskIntoConstraints=NO;
    self.hint.text=@"Mặc định chỉ đọc. Touch/Input không tự thao tác; HTTPS không tự gọi. Chọn nhóm rồi mở script kiểm tra trong Lua Editor.";
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
    cell.detailTextLabel.text=group[@"desc"];
    cell.detailTextLabel.textColor=NKMuted();
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
    if (self.copyText.length) [UIPasteboard generalPasteboard].string=self.copyText;
}

- (void)labShowReport {
    NSDictionary *report=[self labReadReport];
    if (!report) {
        [self labAlert:@"Chưa có báo cáo"
               message:@"Chạy bài kiểm tra trong Lua Editor rồi quay lại Test Lab. Log từng bước có trong Task Center."];
        return;
    }
    NSString *details=[self labReportText:report];
    self.copyText=details;
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
     @"-- NKTouch Test Lab v0.7.16-dev | Generated: %@\n"
      @"-- Default: READ ONLY. Touch / Input / HTTPS will not run without opt-in.\n"
      @"-- To enable interactive tests: choose the correct target via 'Ứng dụng +',\n"
      @"-- then edit bundle ID and physical-pixel coordinates below.\n"
      @"local lab=require(\"nktestlab\")\n"
      @"local opts={\n"
      @"  run_id=\"%@\",\n"
      @"  selected={%@},\n"
      @"  touch={enabled=false,bundle=\"\",tap={x=0,y=0},hold={x=0,y=0,ms=400},\n"
      @"         swipe={x1=0,y1=0,x2=0,y2=0,ms=500}},\n"
      @"  input={enabled=false,bundle=\"\",x=0,y=0,text=\"NKTouch Lab Test\"},\n"
      @"  network={enabled=false},\n"
      @"  vision={}\n"
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
