// NKTouch Lua Workspace UX layer (V7.4)
// V7.4.1 UI polish: dark navy + violet/blue neon, dashboard, script library,
// editor/logs/results and script tools. Core runtime remains V7.4.

#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <QuartzCore/QuartzCore.h>

extern char **environ;

static NSString * const NKLuaScriptsPath = @"/var/mobile/Library/NKTouch/scripts";
static NSString * const NKLuaEditorTool = @"/var/jb/usr/bin/nkeditor";

static UIColor *NKC(NSUInteger rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0
                           green:((rgb >> 8) & 0xff) / 255.0
                            blue:(rgb & 0xff) / 255.0 alpha:1.0];
}
static UIColor *NKBG(void)      { return NKC(0x070B1A); }
static UIColor *NKPanel(void)   { return NKC(0x11172B); }
static UIColor *NKPanel2(void)  { return NKC(0x171F39); }
static UIColor *NKBorder(void)  { return NKC(0x303A63); }
static UIColor *NKPurple(void)  { return NKC(0x8B3DFF); }
static UIColor *NKBlue(void)    { return NKC(0x27A7FF); }
static UIColor *NKGreen(void)   { return NKC(0x25E77A); }
static UIColor *NKRed(void)     { return NKC(0xFF4D64); }
static UIColor *NKMuted(void)   { return NKC(0xA7AEC7); }

static UIImage *NKIcon(NSString *name, CGFloat size) {
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold];
        return [[UIImage systemImageNamed:name] imageByApplyingSymbolConfiguration:cfg];
    }
    return nil;
}

static void NKCard(UIView *v, CGFloat radius) {
    v.backgroundColor = NKPanel();
    v.layer.cornerRadius = radius;
    v.layer.borderWidth = 1.0;
    v.layer.borderColor = NKBorder().CGColor;
    v.layer.shadowColor = NKPurple().CGColor;
    v.layer.shadowOpacity = 0.10;
    v.layer.shadowRadius = 12;
    v.layer.shadowOffset = CGSizeMake(0, 6);
}

@interface NKGradientView : UIView
@property(nonatomic,strong) CAGradientLayer *gradient;
@end
@implementation NKGradientView
- (instancetype)init {
    self = [super init];
    if (self) {
        self.gradient = [CAGradientLayer layer];
        self.gradient.colors = @[(id)NKC(0x5520CE).CGColor, (id)NKC(0x20206D).CGColor, (id)NKC(0x0067D8).CGColor];
        self.gradient.startPoint = CGPointMake(0,0);
        self.gradient.endPoint = CGPointMake(1,1);
        [self.layer insertSublayer:self.gradient atIndex:0];
        self.layer.cornerRadius = 18;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1;
        self.layer.borderColor = NKPurple().CGColor;
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.gradient.frame = self.bounds; }
@end

@interface NKGradientButton : UIButton
@property(nonatomic,strong) CAGradientLayer *gradient;
@end
@implementation NKGradientButton
- (instancetype)init {
    self = [super init];
    if (self) {
        self.gradient = [CAGradientLayer layer];
        self.gradient.colors = @[(id)NKC(0xA147FF).CGColor, (id)NKC(0x6227F0).CGColor];
        self.gradient.startPoint = CGPointMake(0,0.5);
        self.gradient.endPoint = CGPointMake(1,0.5);
        [self.layer insertSublayer:self.gradient atIndex:0];
        self.layer.cornerRadius = 12;
        self.layer.masksToBounds = YES;
        [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.gradient.frame = self.bounds; }
@end

@interface NKMenuCard : UIControl
@end
@implementation NKMenuCard
- (instancetype)initWithIcon:(NSString *)icon title:(NSString *)title subtitle:(NSString *)subtitle tint:(UIColor *)tint {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    NKCard(self, 15);
    UIImageView *iv = [[UIImageView alloc] initWithImage:NKIcon(icon, 23)];
    iv.translatesAutoresizingMaskIntoConstraints = NO; iv.tintColor = tint;
    UILabel *t = [[UILabel alloc] init]; t.translatesAutoresizingMaskIntoConstraints = NO;
    t.text = title; t.textColor = UIColor.whiteColor; t.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    UILabel *s = [[UILabel alloc] init]; s.translatesAutoresizingMaskIntoConstraints = NO;
    s.text = subtitle; s.textColor = NKMuted(); s.font = [UIFont systemFontOfSize:10.5]; s.numberOfLines = 2;
    [self addSubview:iv]; [self addSubview:t]; [self addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [iv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14], [iv.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [iv.widthAnchor constraintEqualToConstant:28], [iv.heightAnchor constraintEqualToConstant:28],
        [t.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14], [t.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [t.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:8],
        [s.leadingAnchor constraintEqualToAnchor:t.leadingAnchor], [s.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [s.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:2]
    ]];
    return self;
}
@end

static NSString *NKLuaRun(NSArray<NSString *> *arguments, int *exitCode) {
    int p[2] = {-1,-1};
    if (pipe(p) != 0) { if (exitCode) *exitCode = 126; return @"Unable to create command pipe."; }
    posix_spawn_file_actions_t a; posix_spawn_file_actions_init(&a);
    posix_spawn_file_actions_adddup2(&a, p[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&a, p[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&a, p[0]); posix_spawn_file_actions_addclose(&a, p[1]);
    NSUInteger argc = arguments.count + 2;
    char **argv = calloc(argc, sizeof(char *));
    argv[0] = strdup(NKLuaEditorTool.UTF8String);
    for (NSUInteger i=0;i<arguments.count;i++) argv[i+1] = strdup(arguments[i].UTF8String);
    argv[arguments.count+1] = NULL;
    pid_t pid = 0; int spawnCode = posix_spawn(&pid, NKLuaEditorTool.UTF8String, &a, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&a); close(p[1]);
    for (NSUInteger i=0;i<arguments.count+1;i++) free(argv[i]); free(argv);
    if (spawnCode != 0) { close(p[0]); if (exitCode) *exitCode=spawnCode; return [NSString stringWithFormat:@"Unable to launch nkeditor (%d).",spawnCode]; }
    NSMutableData *data=[NSMutableData data]; uint8_t buf[4096]; ssize_t n=0;
    while ((n=read(p[0],buf,sizeof(buf)))>0) { [data appendBytes:buf length:(NSUInteger)n]; if(data.length>524288)break; }
    close(p[0]); int status=0; waitpid(pid,&status,0); int code=WIFEXITED(status)?WEXITSTATUS(status):125;
    if(exitCode)*exitCode=code;
    NSString *text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    return text.length?text:(code==0?@"OK":[NSString stringWithFormat:@"Command failed (%d).",code]);
}

static NSArray<NSString *> *NKScripts(void) {
    [[NSFileManager defaultManager] createDirectoryAtPath:NKLuaScriptsPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:NKLuaScriptsPath error:nil]?:@[];
    NSPredicate *p=[NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings){ (void)bindings; return [name.pathExtension.lowercaseString isEqualToString:@"lua"] && ![name hasPrefix:@"."]; }];
    return [[files filteredArrayUsingPredicate:p] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}
static NSString *NKPath(NSString *name){ return [NKLuaScriptsPath stringByAppendingPathComponent:name?:@""]; }
static NSString *NKStarter(void){ return @"-- NKTouch v7.4.1\nlocal nk = require(\"nktouch_v7\")\n\n-- Viết automation ở đây.\n-- nk.tap(120, 450)\n-- nk.sleep(1000)\n"; }
static NSString *NKSafeName(NSString *raw){
    NSString *n=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!n.length)return nil;
    if(![n.pathExtension.lowercaseString isEqualToString:@"lua"])n=[n stringByAppendingPathExtension:@"lua"];
    if([n containsString:@"/"]||[n containsString:@"\\"]||[n containsString:@".."]||[n hasPrefix:@"."])return nil;
    NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"] invertedSet];
    return [n rangeOfCharacterFromSet:bad].location==NSNotFound?n:nil;
}

@class NKLuaLibraryViewController, NKLuaToolsViewController, NKAIPromptViewController;
@interface NKLuaEditorViewController : UIViewController <UITextViewDelegate>
- (instancetype)initWithScriptName:(NSString *)name;
@end

#pragma mark - Dashboard
@interface NKLuaWorkspaceViewController : UIViewController @end
@implementation NKLuaWorkspaceViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@""; self.view.backgroundColor=NKBG();
    if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UIScrollView *scroll=[[UIScrollView alloc]init]; scroll.translatesAutoresizingMaskIntoConstraints=NO; scroll.alwaysBounceVertical=YES;
    UIStackView *stack=[[UIStackView alloc]init]; stack.translatesAutoresizingMaskIntoConstraints=NO; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=12;
    UIView *header=[[UIView alloc]init]; [header.heightAnchor constraintEqualToConstant:62].active=YES;
    UILabel *logo=[[UILabel alloc]init]; logo.translatesAutoresizingMaskIntoConstraints=NO; logo.text=@"NK"; logo.textColor=UIColor.whiteColor; logo.backgroundColor=NKPurple(); logo.font=[UIFont systemFontOfSize:16 weight:UIFontWeightBlack]; logo.textAlignment=NSTextAlignmentCenter; logo.layer.cornerRadius=20; logo.layer.masksToBounds=YES;
    UILabel *brand=[[UILabel alloc]init]; brand.translatesAutoresizingMaskIntoConstraints=NO; brand.text=@"NKTouch"; brand.textColor=UIColor.whiteColor; brand.font=[UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    UILabel *sub=[[UILabel alloc]init]; sub.translatesAutoresizingMaskIntoConstraints=NO; sub.text=@"Automation • Lua • HTTP/JSON"; sub.textColor=NKMuted(); sub.font=[UIFont systemFontOfSize:10.5];
    UILabel *ver=[[UILabel alloc]init]; ver.translatesAutoresizingMaskIntoConstraints=NO; ver.text=@"v7.4.1"; ver.textColor=UIColor.whiteColor; ver.font=[UIFont systemFontOfSize:10 weight:UIFontWeightBold]; ver.backgroundColor=NKC(0x27264B); ver.textAlignment=NSTextAlignmentCenter; ver.layer.cornerRadius=10; ver.layer.masksToBounds=YES;
    [header addSubview:logo];[header addSubview:brand];[header addSubview:sub];[header addSubview:ver];
    [NSLayoutConstraint activateConstraints:@[[logo.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],[logo.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],[logo.widthAnchor constraintEqualToConstant:40],[logo.heightAnchor constraintEqualToConstant:40],[brand.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:10],[brand.topAnchor constraintEqualToAnchor:header.topAnchor constant:10],[sub.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],[sub.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:2],[ver.leadingAnchor constraintEqualToAnchor:brand.trailingAnchor constant:8],[ver.centerYAnchor constraintEqualToAnchor:brand.centerYAnchor],[ver.widthAnchor constraintEqualToConstant:52],[ver.heightAnchor constraintEqualToConstant:21]]];
    NKGradientView *hero=[[NKGradientView alloc]init]; hero.translatesAutoresizingMaskIntoConstraints=NO; [hero.heightAnchor constraintEqualToConstant:170].active=YES;
    UILabel *ht=[[UILabel alloc]init]; ht.translatesAutoresizingMaskIntoConstraints=NO; ht.text=@"Lua Workspace"; ht.textColor=UIColor.whiteColor; ht.font=[UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    UILabel *hs=[[UILabel alloc]init]; hs.translatesAutoresizingMaskIntoConstraints=NO; hs.text=@"Viết • Chạy • Debug • Tự động hoá"; hs.textColor=NKC(0xE4DCFF); hs.font=[UIFont systemFontOfSize:12];
    NKGradientButton *open=[[NKGradientButton alloc]init]; open.translatesAutoresizingMaskIntoConstraints=NO; [open setTitle:@"Mở Workspace  ›" forState:UIControlStateNormal]; [open addTarget:self action:@selector(openWorkspace) forControlEvents:UIControlEventTouchUpInside];
    UIImageView *hi=[[UIImageView alloc]initWithImage:NKIcon(@"chevron.left.forwardslash.chevron.right",42)]; hi.translatesAutoresizingMaskIntoConstraints=NO; hi.tintColor=NKC(0x70E2FF); hi.backgroundColor=NKC(0x2C197C); hi.layer.cornerRadius=18; hi.contentMode=UIViewContentModeCenter;
    [hero addSubview:ht];[hero addSubview:hs];[hero addSubview:open];[hero addSubview:hi];
    [NSLayoutConstraint activateConstraints:@[[ht.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:18],[ht.topAnchor constraintEqualToAnchor:hero.topAnchor constant:28],[hs.leadingAnchor constraintEqualToAnchor:ht.leadingAnchor],[hs.topAnchor constraintEqualToAnchor:ht.bottomAnchor constant:5],[open.leadingAnchor constraintEqualToAnchor:ht.leadingAnchor],[open.topAnchor constraintEqualToAnchor:hs.bottomAnchor constant:17],[open.widthAnchor constraintEqualToConstant:145],[open.heightAnchor constraintEqualToConstant:40],[hi.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-20],[hi.centerYAnchor constraintEqualToAnchor:hero.centerYAnchor],[hi.widthAnchor constraintEqualToConstant:84],[hi.heightAnchor constraintEqualToConstant:84]]];
    NKMenuCard *run=[[NKMenuCard alloc]initWithIcon:@"play.fill" title:@"Chạy tác vụ" subtitle:@"Quản lý & điều khiển" tint:NKGreen()];
    NKMenuCard *rec=[[NKMenuCard alloc]initWithIcon:@"record.circle" title:@"Ghi tác vụ" subtitle:@"Recorder & Script" tint:NKRed()];
    NKMenuCard *lib=[[NKMenuCard alloc]initWithIcon:@"cube.fill" title:@"Thư viện Script" subtitle:@"Mẫu & tiện ích" tint:NKBlue()];
    NKMenuCard *api=[[NKMenuCard alloc]initWithIcon:@"cloud.fill" title:@"API / HTTP" subtitle:@"Gọi HTTP, xử lý JSON" tint:NKBlue()];
    [run addTarget:self action:@selector(openWorkspace) forControlEvents:UIControlEventTouchUpInside]; [lib addTarget:self action:@selector(openWorkspace) forControlEvents:UIControlEventTouchUpInside]; [api addTarget:self action:@selector(openTools) forControlEvents:UIControlEventTouchUpInside]; [rec addTarget:self action:@selector(recordInfo) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *r1=[[UIStackView alloc]initWithArrangedSubviews:@[run,rec]]; r1.axis=UILayoutConstraintAxisHorizontal;r1.spacing=10;r1.distribution=UIStackViewDistributionFillEqually;[r1.heightAnchor constraintEqualToConstant:116].active=YES;
    UIStackView *r2=[[UIStackView alloc]initWithArrangedSubviews:@[lib,api]]; r2.axis=UILayoutConstraintAxisHorizontal;r2.spacing=10;r2.distribution=UIStackViewDistributionFillEqually;[r2.heightAnchor constraintEqualToConstant:116].active=YES;
    UIView *status=[[UIView alloc]init]; NKCard(status,15); [status.heightAnchor constraintEqualToConstant:118].active=YES;
    UILabel *st=[[UILabel alloc]init];st.translatesAutoresizingMaskIntoConstraints=NO;st.text=@"Trạng thái hệ thống";st.textColor=UIColor.whiteColor;st.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    UILabel *ready=[[UILabel alloc]init];ready.translatesAutoresizingMaskIntoConstraints=NO;ready.text=@"● Sẵn sàng";ready.textColor=NKGreen();ready.font=[UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    UILabel *states=[[UILabel alloc]init];states.translatesAutoresizingMaskIntoConstraints=NO;states.numberOfLines=3;states.textAlignment=NSTextAlignmentCenter;states.text=@"▣ Engine                 { } Lua                 ◎ Network\nHoạt động                 v5.4.9                 OK";states.textColor=NKGreen();states.font=[UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightSemibold];
    [status addSubview:st];[status addSubview:ready];[status addSubview:states];
    [NSLayoutConstraint activateConstraints:@[[st.leadingAnchor constraintEqualToAnchor:status.leadingAnchor constant:14],[st.topAnchor constraintEqualToAnchor:status.topAnchor constant:12],[ready.trailingAnchor constraintEqualToAnchor:status.trailingAnchor constant:-14],[ready.centerYAnchor constraintEqualToAnchor:st.centerYAnchor],[states.leadingAnchor constraintEqualToAnchor:status.leadingAnchor constant:8],[states.trailingAnchor constraintEqualToAnchor:status.trailingAnchor constant:-8],[states.topAnchor constraintEqualToAnchor:st.bottomAnchor constant:20]]];
    [stack addArrangedSubview:header];[stack addArrangedSubview:hero];[stack addArrangedSubview:r1];[stack addArrangedSubview:r2];[stack addArrangedSubview:status];
    [scroll addSubview:stack];[self.view addSubview:scroll]; UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:5],[stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:14],[stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-14],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24]]];
}
- (void)openWorkspace { [self.navigationController pushViewController:[[NSClassFromString(@"NKLuaLibraryViewController") alloc] init] animated:YES]; }
- (void)openTools { [self.navigationController pushViewController:[[NSClassFromString(@"NKLuaToolsViewController") alloc] init] animated:YES]; }
- (void)recordInfo { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Ghi tác vụ" message:@"Recorder V2 vẫn giữ nguyên. V7.4.1 chỉ tối ưu UI để không ảnh hưởng engine." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil]; }
@end

#pragma mark - Library
@interface NKLuaLibraryViewController : UIViewController <UITableViewDataSource,UITableViewDelegate,UISearchBarDelegate>
@property(nonatomic,strong) UITableView *table; @property(nonatomic,strong) UISearchBar *search; @property(nonatomic,strong) NSArray<NSString*> *scripts;
@end
@implementation NKLuaLibraryViewController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Lua Workspace";self.view.backgroundColor=NKBG();if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    if(NKScripts().count==0)[NKStarter() writeToFile:NKPath(@"main.lua") atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIButton *plus=[UIButton buttonWithType:UIButtonTypeSystem];[plus setImage:NKIcon(@"plus",17) forState:UIControlStateNormal];plus.tintColor=UIColor.whiteColor;plus.backgroundColor=NKPurple();plus.frame=CGRectMake(0,0,36,36);plus.layer.cornerRadius=18;[plus addTarget:self action:@selector(newScript) forControlEvents:UIControlEventTouchUpInside];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithCustomView:plus];
    self.search=[[UISearchBar alloc]init];self.search.translatesAutoresizingMaskIntoConstraints=NO;self.search.delegate=self;self.search.placeholder=@"Tìm script";self.search.searchBarStyle=UISearchBarStyleMinimal;self.search.barStyle=UIBarStyleBlack;
    UISegmentedControl *seg=[[UISegmentedControl alloc]initWithItems:@[@"Tất cả",@"Đang chạy",@"Yêu thích",@"Thư mục"]];seg.translatesAutoresizingMaskIntoConstraints=NO;seg.selectedSegmentIndex=0;seg.selectedSegmentTintColor=NKPurple();[seg setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor,NSFontAttributeName:[UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    self.table=[[UITableView alloc]initWithFrame:CGRectZero style:UITableViewStylePlain];self.table.translatesAutoresizingMaskIntoConstraints=NO;self.table.backgroundColor=UIColor.clearColor;self.table.separatorStyle=UITableViewCellSeparatorStyleNone;self.table.rowHeight=70;self.table.dataSource=self;self.table.delegate=self;
    [self.view addSubview:self.search];[self.view addSubview:seg];[self.view addSubview:self.table];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[self.search.topAnchor constraintEqualToAnchor:safe.topAnchor],[self.search.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],[self.search.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],[seg.topAnchor constraintEqualToAnchor:self.search.bottomAnchor],[seg.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],[seg.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],[seg.heightAnchor constraintEqualToConstant:34],[self.table.topAnchor constraintEqualToAnchor:seg.bottomAnchor constant:7],[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];[self reloadScripts];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadScripts];}
- (void)reloadScripts { NSArray *all=NKScripts();NSString *q=self.search.text.lowercaseString?:@"";self.scripts=q.length?[all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *n,NSDictionary *b){(void)b;return[n.lowercaseString containsString:q];}]]:all;[self.table reloadData]; }
- (void)searchBar:(UISearchBar*)s textDidChange:(NSString*)t{(void)s;(void)t;[self reloadScripts];}
- (NSInteger)tableView:(UITableView*)t numberOfRowsInSection:(NSInteger)s{(void)t;(void)s;return self.scripts.count+2;}
- (UITableViewCell*)tableView:(UITableView*)tv cellForRowAtIndexPath:(NSIndexPath*)ip{
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.backgroundColor=UIColor.clearColor;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    UIView *card=[[UIView alloc]init];card.translatesAutoresizingMaskIntoConstraints=NO;NKCard(card,13);[cell.contentView addSubview:card];
    UIImageView *icon=[[UIImageView alloc]initWithImage:NKIcon(ip.row<self.scripts.count?@"chevron.left.forwardslash.chevron.right":@"folder.fill",20)];icon.translatesAutoresizingMaskIntoConstraints=NO;icon.tintColor=ip.row<self.scripts.count?NKPurple():NKC(0xFFB51D);
    UILabel *name=[[UILabel alloc]init];name.translatesAutoresizingMaskIntoConstraints=NO;name.textColor=UIColor.whiteColor;name.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    UILabel *meta=[[UILabel alloc]init];meta.translatesAutoresizingMaskIntoConstraints=NO;meta.textColor=NKMuted();meta.font=[UIFont systemFontOfSize:10.5];
    UIImageView *chev=[[UIImageView alloc]initWithImage:NKIcon(@"chevron.right",13)];chev.translatesAutoresizingMaskIntoConstraints=NO;chev.tintColor=NKMuted();
    if(ip.row<self.scripts.count){NSString *n=self.scripts[ip.row];name.text=n;NSDictionary *a=[[NSFileManager defaultManager]attributesOfItemAtPath:NKPath(n) error:nil];meta.text=[NSString stringWithFormat:@"%.1f KB • Lua",MAX(.1,[a fileSize]/1024.0)];}else{BOOL tools=ip.row==self.scripts.count;name.text=tools?@"Tools":@"Samples";meta.text=tools?@"Công cụ Script":@"Ví dụ mẫu";}
    [card addSubview:icon];[card addSubview:name];[card addSubview:meta];[card addSubview:chev];
    [NSLayoutConstraint activateConstraints:@[[card.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],[card.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],[card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:5],[card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-5],[icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],[icon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],[icon.widthAnchor constraintEqualToConstant:30],[name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],[name.topAnchor constraintEqualToAnchor:card.topAnchor constant:11],[meta.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],[meta.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:2],[chev.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],[chev.centerYAnchor constraintEqualToAnchor:card.centerYAnchor]]];return cell;
}
- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{(void)tv;if(ip.row<self.scripts.count){[self.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:self.scripts[ip.row]] animated:YES];}else if(ip.row==self.scripts.count){[self.navigationController pushViewController:[[NSClassFromString(@"NKLuaToolsViewController") alloc]init] animated:YES];}}
- (void)newScript {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Script mới" message:@"Đặt tên file Lua" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"script-name.lua";f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];__weak typeof(self) w=self;[a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Tạo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){(void)x;NSString *n=NKSafeName(a.textFields.firstObject.text?:@"");if(!n.length)return;NSString *p=NKPath(n);if(![[NSFileManager defaultManager]fileExistsAtPath:p])[NKStarter() writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];[w reloadScripts];[w.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:n] animated:YES];}]];[self presentViewController:a animated:YES completion:nil];}
@end

#pragma mark - Editor
@interface NKLuaEditorViewController ()
@property(nonatomic,copy) NSString *scriptName;@property(nonatomic,strong) UISegmentedControl *mode;@property(nonatomic,strong) UITextView *codeView;@property(nonatomic,strong) UITextView *console;@property(nonatomic,strong) UIView *editor;@property(nonatomic,strong) UIView *logs;@property(nonatomic,strong) UIView *result;@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,assign) BOOL dirty;
@end
@implementation NKLuaEditorViewController
- (instancetype)initWithScriptName:(NSString*)name{self=[super init];if(self)self.scriptName=name;return self;}
- (UIButton*)button:(NSString*)title purple:(BOOL)purple {UIButton *b=purple?[[NKGradientButton alloc]init]:[UIButton buttonWithType:UIButtonTypeSystem];b.translatesAutoresizingMaskIntoConstraints=NO;[b setTitle:title forState:UIControlStateNormal];[b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];if(!purple){b.backgroundColor=NKPanel2();b.layer.cornerRadius=11;b.layer.borderWidth=1;b.layer.borderColor=NKBorder().CGColor;}return b;}
- (UIButton*)tool:(NSString*)title icon:(NSString*)icon {UIButton *b=[self button:title purple:NO];[b setImage:NKIcon(icon,14) forState:UIControlStateNormal];b.tintColor=NKMuted();b.titleLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];b.titleLabel.numberOfLines=2;b.titleLabel.textAlignment=NSTextAlignmentCenter;return b;}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=self.scriptName;self.view.backgroundColor=NKBG();if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.mode=[[UISegmentedControl alloc]initWithItems:@[@"Editor",@"Logs",@"Kết quả"]];self.mode.translatesAutoresizingMaskIntoConstraints=NO;self.mode.selectedSegmentIndex=0;self.mode.selectedSegmentTintColor=NKPurple();self.mode.backgroundColor=NKPanel2();[self.mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    self.editor=[[UIView alloc]init];self.editor.translatesAutoresizingMaskIntoConstraints=NO;
    self.codeView=[[UITextView alloc]init];self.codeView.translatesAutoresizingMaskIntoConstraints=NO;self.codeView.delegate=self;self.codeView.font=[UIFont monospacedSystemFontOfSize:13.2 weight:UIFontWeightRegular];self.codeView.backgroundColor=NKC(0x0A1020);self.codeView.textColor=NKC(0xE8ECFF);self.codeView.tintColor=NKPurple();self.codeView.layer.cornerRadius=13;self.codeView.layer.borderWidth=1;self.codeView.layer.borderColor=NKBorder().CGColor;self.codeView.textContainerInset=UIEdgeInsetsMake(12,12,12,12);self.codeView.autocorrectionType=UITextAutocorrectionTypeNo;self.codeView.autocapitalizationType=UITextAutocapitalizationTypeNone;self.codeView.smartQuotesType=UITextSmartQuotesTypeNo;self.codeView.smartDashesType=UITextSmartDashesTypeNo;
    UIView *syntaxBar=[[UIView alloc]init];syntaxBar.translatesAutoresizingMaskIntoConstraints=NO;NKCard(syntaxBar,10);UIImageView *ok=[[UIImageView alloc]initWithImage:NKIcon(@"checkmark.circle.fill",15)];ok.translatesAutoresizingMaskIntoConstraints=NO;ok.tintColor=NKGreen();self.syntax=[[UILabel alloc]init];self.syntax.translatesAutoresizingMaskIntoConstraints=NO;self.syntax.text=@"Sẵn sàng";self.syntax.textColor=NKGreen();self.syntax.font=[UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];[syntaxBar addSubview:ok];[syntaxBar addSubview:self.syntax];
    UIButton *run=[self button:@"▶  Chạy" purple:YES];[run addTarget:self action:@selector(runTapped) forControlEvents:UIControlEventTouchUpInside];UIButton *stop=[self button:@"■  Dừng" purple:NO];[stop addTarget:self action:@selector(stopTapped) forControlEvents:UIControlEventTouchUpInside];UIButton *check=[self button:@"✓  Check" purple:NO];[check addTarget:self action:@selector(checkTapped) forControlEvents:UIControlEventTouchUpInside];UIStackView *primary=[[UIStackView alloc]initWithArrangedSubviews:@[run,stop,check]];primary.translatesAutoresizingMaskIntoConstraints=NO;primary.axis=UILayoutConstraintAxisHorizontal;primary.spacing=8;primary.distribution=UIStackViewDistributionFillEqually;
    UIButton *save=[self tool:@"Lưu" icon:@"square.and.arrow.down"];[save addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];UIButton *ai=[self tool:@"AI Sinh Code" icon:@"sparkles"];ai.tintColor=NKC(0xFF78E7);[ai addTarget:self action:@selector(aiTapped) forControlEvents:UIControlEventTouchUpInside];UIButton *format=[self tool:@"Định dạng" icon:@"slider.horizontal.3"];format.tintColor=NKBlue();[format addTarget:self action:@selector(formatTapped) forControlEvents:UIControlEventTouchUpInside];UIButton *more=[self tool:@"Thêm" icon:@"square.grid.2x2"];[more addTarget:self action:@selector(toolsTapped) forControlEvents:UIControlEventTouchUpInside];UIStackView *tools=[[UIStackView alloc]initWithArrangedSubviews:@[save,ai,format,more]];tools.translatesAutoresizingMaskIntoConstraints=NO;tools.axis=UILayoutConstraintAxisHorizontal;tools.spacing=8;tools.distribution=UIStackViewDistributionFillEqually;
    [self.editor addSubview:self.codeView];[self.editor addSubview:syntaxBar];[self.editor addSubview:primary];[self.editor addSubview:tools];
    [NSLayoutConstraint activateConstraints:@[[self.codeView.topAnchor constraintEqualToAnchor:self.editor.topAnchor],[self.codeView.leadingAnchor constraintEqualToAnchor:self.editor.leadingAnchor],[self.codeView.trailingAnchor constraintEqualToAnchor:self.editor.trailingAnchor],[self.codeView.bottomAnchor constraintEqualToAnchor:syntaxBar.topAnchor constant:-7],[syntaxBar.leadingAnchor constraintEqualToAnchor:self.editor.leadingAnchor],[syntaxBar.trailingAnchor constraintEqualToAnchor:self.editor.trailingAnchor],[syntaxBar.heightAnchor constraintEqualToConstant:34],[ok.leadingAnchor constraintEqualToAnchor:syntaxBar.leadingAnchor constant:10],[ok.centerYAnchor constraintEqualToAnchor:syntaxBar.centerYAnchor],[self.syntax.leadingAnchor constraintEqualToAnchor:ok.trailingAnchor constant:5],[self.syntax.centerYAnchor constraintEqualToAnchor:syntaxBar.centerYAnchor],[primary.topAnchor constraintEqualToAnchor:syntaxBar.bottomAnchor constant:8],[primary.leadingAnchor constraintEqualToAnchor:self.editor.leadingAnchor],[primary.trailingAnchor constraintEqualToAnchor:self.editor.trailingAnchor],[primary.heightAnchor constraintEqualToConstant:45],[tools.topAnchor constraintEqualToAnchor:primary.bottomAnchor constant:8],[tools.leadingAnchor constraintEqualToAnchor:self.editor.leadingAnchor],[tools.trailingAnchor constraintEqualToAnchor:self.editor.trailingAnchor],[tools.heightAnchor constraintEqualToConstant:60],[tools.bottomAnchor constraintEqualToAnchor:self.editor.bottomAnchor]]];
    [self buildLogs];[self buildResult];[self.view addSubview:self.mode];[self.view addSubview:self.editor];[self.view addSubview:self.logs];[self.view addSubview:self.result];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[self.mode.topAnchor constraintEqualToAnchor:safe.topAnchor constant:5],[self.mode.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],[self.mode.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],[self.mode.heightAnchor constraintEqualToConstant:35],[self.editor.topAnchor constraintEqualToAnchor:self.mode.bottomAnchor constant:8],[self.editor.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],[self.editor.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],[self.editor.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-8],[self.logs.topAnchor constraintEqualToAnchor:self.mode.bottomAnchor constant:8],[self.logs.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],[self.logs.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],[self.logs.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10],[self.result.topAnchor constraintEqualToAnchor:self.mode.bottomAnchor constant:8],[self.result.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],[self.result.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],[self.result.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10]]];self.logs.hidden=YES;self.result.hidden=YES;self.codeView.text=[NSString stringWithContentsOfFile:NKPath(self.scriptName) encoding:NSUTF8StringEncoding error:nil]?:NKStarter();[self highlight];
}
- (void)buildLogs {self.logs=[[UIView alloc]init];self.logs.translatesAutoresizingMaskIntoConstraints=NO;self.console=[[UITextView alloc]init];self.console.translatesAutoresizingMaskIntoConstraints=NO;self.console.editable=NO;self.console.font=[UIFont monospacedSystemFontOfSize:11.2 weight:UIFontWeightRegular];self.console.backgroundColor=NKC(0x0A1020);self.console.textColor=NKC(0xC9D4FF);self.console.layer.cornerRadius=13;self.console.layer.borderWidth=1;self.console.layer.borderColor=NKBorder().CGColor;self.console.text=@"[NKTouch] Sẵn sàng.\n";UIView *state=[[UIView alloc]init];state.translatesAutoresizingMaskIntoConstraints=NO;NKCard(state,12);self.runState=[[UILabel alloc]init];self.runState.translatesAutoresizingMaskIntoConstraints=NO;self.runState.text=@"● Sẵn sàng";self.runState.textColor=NKGreen();self.runState.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];self.progress=[[UIProgressView alloc]initWithProgressViewStyle:UIProgressViewStyleDefault];self.progress.translatesAutoresizingMaskIntoConstraints=NO;self.progress.progressTintColor=NKGreen();self.progress.trackTintColor=NKC(0x203148);UIButton *stop=[self button:@"■  Dừng" purple:NO];[stop addTarget:self action:@selector(stopTapped) forControlEvents:UIControlEventTouchUpInside];[self.logs addSubview:self.console];[self.logs addSubview:state];[state addSubview:self.runState];[state addSubview:self.progress];[self.logs addSubview:stop];[NSLayoutConstraint activateConstraints:@[[self.console.topAnchor constraintEqualToAnchor:self.logs.topAnchor],[self.console.leadingAnchor constraintEqualToAnchor:self.logs.leadingAnchor],[self.console.trailingAnchor constraintEqualToAnchor:self.logs.trailingAnchor],[self.console.bottomAnchor constraintEqualToAnchor:state.topAnchor constant:-8],[state.leadingAnchor constraintEqualToAnchor:self.logs.leadingAnchor],[state.trailingAnchor constraintEqualToAnchor:self.logs.trailingAnchor],[state.bottomAnchor constraintEqualToAnchor:stop.topAnchor constant:-8],[state.heightAnchor constraintEqualToConstant:66],[self.runState.leadingAnchor constraintEqualToAnchor:state.leadingAnchor constant:12],[self.runState.topAnchor constraintEqualToAnchor:state.topAnchor constant:11],[self.progress.leadingAnchor constraintEqualToAnchor:state.leadingAnchor constant:12],[self.progress.trailingAnchor constraintEqualToAnchor:state.trailingAnchor constant:-12],[self.progress.bottomAnchor constraintEqualToAnchor:state.bottomAnchor constant:-13],[stop.leadingAnchor constraintEqualToAnchor:self.logs.leadingAnchor],[stop.trailingAnchor constraintEqualToAnchor:self.logs.trailingAnchor],[stop.bottomAnchor constraintEqualToAnchor:self.logs.bottomAnchor],[stop.heightAnchor constraintEqualToConstant:46]]];}
- (void)buildResult {self.result=[[UIView alloc]init];self.result.translatesAutoresizingMaskIntoConstraints=NO;UIView *card=[[UIView alloc]init];card.translatesAutoresizingMaskIntoConstraints=NO;NKCard(card,16);UIImageView *i=[[UIImageView alloc]initWithImage:NKIcon(@"checkmark.seal.fill",34)];i.translatesAutoresizingMaskIntoConstraints=NO;i.tintColor=NKGreen();UILabel *t=[[UILabel alloc]init];t.translatesAutoresizingMaskIntoConstraints=NO;t.text=@"Kết quả tác vụ";t.textColor=UIColor.whiteColor;t.font=[UIFont systemFontOfSize:18 weight:UIFontWeightBold];UILabel *s=[[UILabel alloc]init];s.translatesAutoresizingMaskIntoConstraints=NO;s.text=@"Chưa có kết quả. Chạy script để xem trạng thái tại đây.";s.textColor=NKMuted();s.numberOfLines=0;s.font=[UIFont systemFontOfSize:13];[self.result addSubview:card];[card addSubview:i];[card addSubview:t];[card addSubview:s];[NSLayoutConstraint activateConstraints:@[[card.topAnchor constraintEqualToAnchor:self.result.topAnchor],[card.leadingAnchor constraintEqualToAnchor:self.result.leadingAnchor],[card.trailingAnchor constraintEqualToAnchor:self.result.trailingAnchor],[card.heightAnchor constraintEqualToConstant:180],[i.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],[i.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],[t.leadingAnchor constraintEqualToAnchor:i.trailingAnchor constant:12],[t.centerYAnchor constraintEqualToAnchor:i.centerYAnchor],[s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],[s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],[s.topAnchor constraintEqualToAnchor:i.bottomAnchor constant:18]]];}
- (void)modeChanged{self.editor.hidden=self.mode.selectedSegmentIndex!=0;self.logs.hidden=self.mode.selectedSegmentIndex!=1;self.result.hidden=self.mode.selectedSegmentIndex!=2;if(self.mode.selectedSegmentIndex==1)[self logsTapped];}
- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;self.syntax.text=@"Chưa lưu";self.syntax.textColor=NKC(0xFFB545);[self highlight];}
- (void)highlight{if(!self.codeView.text.length)return;NSRange sel=self.codeView.selectedRange;NSMutableAttributedString *a=[[NSMutableAttributedString alloc]initWithString:self.codeView.text attributes:@{NSFontAttributeName:[UIFont monospacedSystemFontOfSize:13.2 weight:UIFontWeightRegular],NSForegroundColorAttributeName:NKC(0xE8ECFF)}];NSArray *rules=@[@[@"--[^\\n]*",NKGreen()],@[@"\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'",NKC(0xFFAD66)],@[@"\\b(local|function|end|if|then|else|elseif|for|while|return|true|false|nil)\\b",NKC(0xE875FF)],@[@"\\bnk\\.[A-Za-z0-9_\\.]+",NKC(0x6CD7FF)]];for(NSArray *r in rules){NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:r[0] options:0 error:nil];[re enumerateMatchesInString:a.string options:0 range:NSMakeRange(0,a.length) usingBlock:^(NSTextCheckingResult *m,NSMatchingFlags f,BOOL *stop){(void)f;(void)stop;if(m.range.location!=NSNotFound)[a addAttribute:NSForegroundColorAttributeName value:r[1] range:m.range];}];}self.codeView.attributedText=a;if(sel.location<=a.length)self.codeView.selectedRange=sel;}
- (BOOL)save{NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;self.syntax.text=ok?@"Đã lưu":@"Lưu lỗi";self.syntax.textColor=ok?NKGreen():NKRed();return ok;}
- (void)saveTapped{[self save];}
- (void)command:(NSArray*)args state:(NSString*)state done:(void(^)(int,NSString*))done{[self.view endEditing:YES];self.runState.text=state;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{int code=0;NSString *o=NKLuaRun(args,&code);dispatch_async(dispatch_get_main_queue(),^{if(done)done(code,o?:@"");});});}
- (NSInteger)line:(NSString*)o{NSRegularExpression *r=[NSRegularExpression regularExpressionWithPattern:@":([0-9]+):" options:0 error:nil];NSTextCheckingResult *m=[r firstMatchInString:o options:0 range:NSMakeRange(0,o.length)];return(!m||m.numberOfRanges<2)?NSNotFound:[[o substringWithRange:[m rangeAtIndex:1]]integerValue];}
- (void)jump:(NSInteger)line{if(line<=0)return;NSString *t=self.codeView.text?:@"";NSUInteger p=0;NSInteger n=1;while(n<line&&p<t.length){NSRange r=[t rangeOfString:@"\n" options:0 range:NSMakeRange(p,t.length-p)];if(r.location==NSNotFound)break;p=NSMaxRange(r);n++;}NSRange lr=[t lineRangeForRange:NSMakeRange(MIN(p,t.length),0)];self.codeView.selectedRange=lr;[self.codeView scrollRangeToVisible:lr];}
- (void)checkTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){w.console.text=o;w.syntax.text=c==0?@"Cú pháp hợp lệ":@"Lỗi cú pháp";w.syntax.textColor=c==0?NKGreen():NKRed();if(c!=0){NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];}}];}
- (void)runTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){if(c!=0){w.console.text=o;w.syntax.text=@"Lỗi cú pháp";w.syntax.textColor=NKRed();NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];return;}[w command:@[@"run",w.scriptName] state:@"● Đang chạy…" done:^(int rc,NSString *ro){w.console.text=ro;w.mode.selectedSegmentIndex=1;[w modeChanged];w.runState.text=rc==0?@"● Đang chạy…":@"● Chạy lỗi";w.runState.textColor=rc==0?NKGreen():NKRed();[w.progress setProgress:rc==0?.18:0 animated:YES];}];}];}
- (void)stopTapped{__weak typeof(self)w=self;[self command:@[@"stop"] state:@"Đang dừng…" done:^(int c,NSString *o){w.console.text=o;w.runState.text=c==0?@"Đã dừng":@"Dừng lỗi";w.runState.textColor=c==0?NKMuted():NKRed();[w.progress setProgress:0 animated:YES];}];}
- (void)logsTapped{__weak typeof(self)w=self;[self command:@[@"logs"] state:@"Đang tải logs…" done:^(int c,NSString *o){w.console.text=o;w.runState.text=c==0?@"● Theo dõi logs":@"Log lỗi";w.runState.textColor=c==0?NKGreen():NKRed();}];}
- (void)formatTapped{NSString *text=self.codeView.text?:@"";NSMutableArray *lines=[[text componentsSeparatedByString:@"\n"]mutableCopy];NSInteger d=0;for(NSUInteger i=0;i<lines.count;i++){NSString *l=[lines[i]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if([l hasPrefix:@"end"]||[l hasPrefix:@"else"]||[l hasPrefix:@"elseif"])d=MAX(0,d-1);NSString *ind=[@"" stringByPaddingToLength:(NSUInteger)d*2 withString:@" " startingAtIndex:0];lines[i]=[ind stringByAppendingString:l];if([l hasSuffix:@"then"]||[l hasSuffix:@"do"]||[l hasPrefix:@"function "]||[l hasPrefix:@"local function "])d++;if([l hasPrefix:@"else"]||[l hasPrefix:@"elseif"])d++;}self.codeView.text=[lines componentsJoinedByString:@"\n"];self.dirty=YES;[self highlight];self.syntax.text=@"Đã định dạng • Chưa lưu";self.syntax.textColor=NKC(0xFFB545);}
- (void)aiTapped{UIViewController *v=[[NSClassFromString(@"NKAIPromptViewController") alloc]init];__weak typeof(self)w=self;if([v respondsToSelector:NSSelectorFromString(@"setCompletion:")]){void(^b)(NSString*)=^(NSString *g){if(g.length){w.codeView.text=g;w.dirty=YES;[w highlight];w.syntax.text=@"AI Draft • Chưa lưu";w.syntax.textColor=NKC(0xFF86EC);}};[v setValue:[b copy] forKey:@"completion"];}UINavigationController *n=[[UINavigationController alloc]initWithRootViewController:v];n.modalPresentationStyle=UIModalPresentationPageSheet;[self presentViewController:n animated:YES completion:nil];}
- (void)toolsTapped{[self.navigationController pushViewController:[[NSClassFromString(@"NKLuaToolsViewController") alloc]init] animated:YES];}
- (void)viewWillDisappear:(BOOL)a{[super viewWillDisappear:a];if(self.dirty)[self save];}
@end

#pragma mark - AI prompt
@interface NKAIPromptViewController : UIViewController <UITextViewDelegate>
@property(nonatomic,strong) UITextView *prompt;@property(nonatomic,strong) UILabel *count;@property(nonatomic,copy) void(^completion)(NSString*);
@end
@implementation NKAIPromptViewController
- (void)viewDidLoad{[super viewDidLoad];self.title=@"✨ AI Sinh Lua";self.view.backgroundColor=NKBG();if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];UILabel *s=[[UILabel alloc]init];s.translatesAutoresizingMaskIntoConstraints=NO;s.text=@"Mô tả tác vụ bạn muốn, hệ thống tạo khung script Lua để chỉnh tiếp.";s.textColor=NKMuted();s.font=[UIFont systemFontOfSize:12];s.numberOfLines=0;UIView *card=[[UIView alloc]init];card.translatesAutoresizingMaskIntoConstraints=NO;NKCard(card,14);self.prompt=[[UITextView alloc]init];self.prompt.translatesAutoresizingMaskIntoConstraints=NO;self.prompt.delegate=self;self.prompt.backgroundColor=UIColor.clearColor;self.prompt.textColor=UIColor.whiteColor;self.prompt.tintColor=NKPurple();self.prompt.font=[UIFont systemFontOfSize:14];self.prompt.text=@"Mở Safari, vào trang web, chờ tải xong rồi tiếp tục thao tác.";self.count=[[UILabel alloc]init];self.count.translatesAutoresizingMaskIntoConstraints=NO;self.count.textColor=NKMuted();self.count.font=[UIFont systemFontOfSize:10.5];self.count.text=@"63 / 500";NKGradientButton *g=[[NKGradientButton alloc]init];g.translatesAutoresizingMaskIntoConstraints=NO;[g setTitle:@"✨  Tạo Script" forState:UIControlStateNormal];[g addTarget:self action:@selector(generate) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:s];[self.view addSubview:card];[card addSubview:self.prompt];[card addSubview:self.count];[self.view addSubview:g];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;[NSLayoutConstraint activateConstraints:@[[s.topAnchor constraintEqualToAnchor:safe.topAnchor constant:18],[s.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18],[s.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18],[card.topAnchor constraintEqualToAnchor:s.bottomAnchor constant:16],[card.leadingAnchor constraintEqualToAnchor:s.leadingAnchor],[card.trailingAnchor constraintEqualToAnchor:s.trailingAnchor],[card.heightAnchor constraintEqualToConstant:180],[self.prompt.topAnchor constraintEqualToAnchor:card.topAnchor constant:8],[self.prompt.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:8],[self.prompt.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-8],[self.prompt.bottomAnchor constraintEqualToAnchor:self.count.topAnchor constant:-4],[self.count.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],[self.count.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-9],[g.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:18],[g.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],[g.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],[g.heightAnchor constraintEqualToConstant:52]]];}
- (void)textViewDidChange:(UITextView*)v{if(v.text.length>500)v.text=[v.text substringToIndex:500];self.count.text=[NSString stringWithFormat:@"%lu / 500",(unsigned long)v.text.length];}
- (void)generate{NSString *p=[[self.prompt.text?:@"" stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSString *g=[NSString stringWithFormat:@"-- NKTouch v7.4.1 • AI draft\nlocal nk = require(\"nktouch_v7\")\n\n-- Yêu cầu: %@\n-- TODO: hoàn thiện các bước automation ở đây.\n-- nk.tap(120, 450)\n-- nk.sleep(1000)\n",p.length?p:@"(không có mô tả)"];if(self.completion)self.completion(g);[self dismissViewControllerAnimated:YES completion:nil];}
- (void)close{[self dismissViewControllerAnimated:YES completion:nil];}
@end

#pragma mark - Tools
@interface NKLuaToolsViewController : UIViewController @end
@implementation NKLuaToolsViewController
- (void)viewDidLoad{[super viewDidLoad];self.title=@"Công cụ Script";self.view.backgroundColor=NKBG();if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;NSArray *items=@[@[@"checkmark.shield.fill",@"Kiểm tra cú pháp",@"Lua Check",NKGreen()],@[@"curlybraces",@"Định dạng mã",@"Format",NKC(0xC26BFF)],@[@"magnifyingglass",@"Tìm & Thay thế",@"Find / Replace",NKBlue()],@[@"square.stack.3d.up.fill",@"Chèn mẫu",@"Snippet",NKC(0xF17CFF)],@[@"book.fill",@"Tài liệu API",@"nk.*",NKC(0xBE75FF)],@[@"shippingbox.fill",@"Ví dụ mẫu",@"Samples",NKC(0xC15BFF)]];UIStackView *outer=[[UIStackView alloc]init];outer.translatesAutoresizingMaskIntoConstraints=NO;outer.axis=UILayoutConstraintAxisVertical;outer.spacing=10;for(NSInteger r=0;r<3;r++){UIStackView *h=[[UIStackView alloc]init];h.axis=UILayoutConstraintAxisHorizontal;h.spacing=10;h.distribution=UIStackViewDistributionFillEqually;for(NSInteger c=0;c<2;c++){NSInteger x=r*2+c;NSArray *it=items[x];NKMenuCard *card=[[NKMenuCard alloc]initWithIcon:it[0] title:it[1] subtitle:it[2] tint:it[3]];card.tag=x;[card.heightAnchor constraintEqualToConstant:116].active=YES;[card addTarget:self action:@selector(tool:) forControlEvents:UIControlEventTouchUpInside];[h addArrangedSubview:card];}[outer addArrangedSubview:h];}[self.view addSubview:outer];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;[NSLayoutConstraint activateConstraints:@[[outer.topAnchor constraintEqualToAnchor:safe.topAnchor constant:18],[outer.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:14],[outer.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-14]]];}
- (void)tool:(UIControl*)c{NSArray *t=@[@"Kiểm tra cú pháp",@"Định dạng mã",@"Tìm & Thay thế",@"Chèn mẫu",@"Tài liệu API",@"Ví dụ mẫu"];NSString *m=c.tag==4?@"API catalog: /var/jb/usr/share/nktouch/nktouch-api.tsv":c.tag==5?@"Mẫu tap / image / color / OCR có trong nkeditor. HTTP/JSON giữ từ V7.4.":@"Mở một script trong Editor để dùng công cụ này trực tiếp.";UIAlertController *a=[UIAlertController alertControllerWithTitle:t[MIN(c.tag,(NSInteger)t.count-1)] message:m preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
@end
