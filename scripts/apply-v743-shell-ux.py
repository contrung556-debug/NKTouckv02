#!/usr/bin/env python3
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v743-shell-ux.py <upstream-dir>")

root = Path(sys.argv[1])
settings = root / "zxtouch/zxtouch/Settings/SettingsPageViewController.m"
scene = root / "zxtouch/zxtouch/SceneDelegate.m"
if not settings.exists() or not scene.exists():
    raise SystemExit("missing upstream SettingsPageViewController.m or SceneDelegate.m")

s = settings.read_text()
if "V7.4.3 shell UX rebuild" in s:
    print("V7.4.3 shell UX rebuild already applied")
    raise SystemExit(0)

# Theme helpers are deliberately separate from the Lua Workspace helpers so the
# legacy settings controller can be restyled without relying on declarations
# appended later in the translation unit.
needle = "static UIImage *ZXSettingsSymbol(NSString *name) {\n"
if needle not in s:
    raise SystemExit("settings symbol marker missing")
helpers = r'''// V7.4.3 shell UX rebuild: one NKTouch visual system across home/workspace/settings.
static UIColor *NKShellColor(NSUInteger rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0
                           green:((rgb >> 8) & 0xff) / 255.0
                            blue:(rgb & 0xff) / 255.0 alpha:1.0];
}
static UIColor *NKShellBG(void)     { return NKShellColor(0x070B1A); }
static UIColor *NKShellPanel(void)  { return NKShellColor(0x11172B); }
static UIColor *NKShellBorder(void) { return NKShellColor(0x293354); }
static UIColor *NKShellPurple(void) { return NKShellColor(0x8B3DFF); }
static UIColor *NKShellBlue(void)   { return NKShellColor(0x27A7FF); }
static UIColor *NKShellMuted(void)  { return NKShellColor(0x9DA7C4); }

'''
s = s.replace(needle, helpers + needle, 1)

# Settings is now a native NKTouch settings surface instead of a white ZXTouch
# screen. The dark-mode row is removed because the NKTouch shell has a fixed
# dark identity; the old handler stays available internally for compatibility.
s = s.replace('self.title = @"Settings";', 'self.title = @"Cài đặt";\n    self.view.backgroundColor = NKShellBG();\n    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;', 1)
sections_old = 'sections = @[NSLocalizedString(@"remoteManagement", nil), NSLocalizedString(@"control", nil), @"Automation", NSLocalizedString(@"script", nil), @"Appearance", @"About"];'
sections_new = 'sections = @[@"KẾT NỐI", @"ĐIỀU KHIỂN", @"TỰ ĐỘNG HÓA", @"SCRIPT", @"GIỚI THIỆU"];'
count = s.count(sections_old)
if count != 2:
    raise SystemExit(f"expected 2 settings section models, found {count}")
s = s.replace(sections_old, sections_new)

dark_block = '''        @[\n            @{@"type": @(SETTING_CELL_SWITCH), @"title": @"Dark Mode", @"switch_click_handler": NSStringFromSelector(@selector(handleDarkModeToggle:)), @"switch_init_status": @(darkMode)}\n        ],\n'''
count = s.count(dark_block)
if count != 2:
    raise SystemExit(f"expected 2 legacy Dark Mode blocks, found {count}")
s = s.replace(dark_block, '')

s = s.replace('    BOOL darkMode = [self darkModeEnabled];\n', '')
s = s.replace('_tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];', '_tableView.backgroundColor = NKShellBG();')
s = s.replace('_tableView.rowHeight = 54;', '_tableView.rowHeight = 58;\n    _tableView.separatorColor = NKShellBorder();\n    if (@available(iOS 15.0, *)) _tableView.sectionHeaderTopPadding = 6;')
s = s.replace('cell.iconView.tintColor = [UIColor systemBlueColor];', 'cell.iconView.tintColor = NKShellBlue();')
s = s.replace('cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];', 'cell.backgroundColor = NKShellPanel();')
s = s.replace('cell.subTitle.textColor = [UIColor secondaryLabelColor];', 'cell.subTitle.textColor = NKShellMuted();')
s = s.replace('title.textColor = [UIColor secondaryLabelColor];', 'title.textColor = NKShellMuted();')
s = s.replace('cell.title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];', 'cell.title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];\n        cell.title.textColor = UIColor.whiteColor;')
s = s.replace('        [cell.switchBtn setOn:[cellInfo[@"switch_init_status"] boolValue]];', '        cell.switchBtn.onTintColor = NKShellPurple();\n        [cell.switchBtn setOn:[cellInfo[@"switch_init_status"] boolValue]];')
s = s.replace('    if ([title containsString:@"ZXTouch"]) return @"info.circle";', '    if ([title containsString:@"ZXTouch"] || [title containsString:@"NKTouch"]) return @"info.circle.fill";')

# Polish the Settings navigation bar each time the tab is shown. Keep all
# existing setting actions/handlers intact.
view_will = '''- (void)viewWillAppear:(BOOL)animated {\n    [super viewWillAppear:animated];'''
view_will_new = '''- (void)viewWillAppear:(BOOL)animated {\n    [super viewWillAppear:animated];\n    self.view.backgroundColor = NKShellBG();\n    self.tableView.backgroundColor = NKShellBG();\n    if (@available(iOS 13.0, *)) {\n        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;\n        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];\n        [appearance configureWithOpaqueBackground];\n        appearance.backgroundColor = NKShellBG();\n        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};\n        appearance.shadowColor = UIColor.clearColor;\n        self.navigationController.navigationBar.standardAppearance = appearance;\n        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;\n        self.navigationController.navigationBar.compactAppearance = appearance;\n        self.navigationController.navigationBar.tintColor = NKShellBlue();\n    }'''
if view_will not in s:
    raise SystemExit("settings viewWillAppear marker missing")
s = s.replace(view_will, view_will_new, 1)

# Replace the intermediate dashboard with a cleaner root dashboard designed for
# the phone-sized flow seen in the user's video. It is also safe when opened
# from Settings. Pushed workspace/editor screens hide the bottom tab bar.
dashboard = r'''#pragma mark - Dashboard
@interface NKLuaWorkspaceViewController : UIViewController
@property(nonatomic,strong) UILabel *taskStateLabel;
@property(nonatomic,strong) UILabel *taskDetailLabel;
@end
@implementation NKLuaWorkspaceViewController
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [self refreshTaskState];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}
- (UILabel *)nkLabel:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *l=[[UILabel alloc]init];l.translatesAutoresizingMaskIntoConstraints=NO;l.text=text;l.textColor=color;l.font=[UIFont systemFontOfSize:size weight:weight];return l;
}
- (UIView *)statusPill:(NSString *)title value:(NSString *)value tint:(UIColor *)tint {
    UIView *v=[[UIView alloc]init];v.translatesAutoresizingMaskIntoConstraints=NO;v.backgroundColor=NKC(0x0D1428);v.layer.cornerRadius=12;v.layer.borderWidth=1;v.layer.borderColor=NKBorder().CGColor;
    UILabel *t=[self nkLabel:title size:9.5 weight:UIFontWeightSemibold color:NKMuted()];UILabel *x=[self nkLabel:value size:11.5 weight:UIFontWeightBold color:tint];
    [v addSubview:t];[v addSubview:x];[NSLayoutConstraint activateConstraints:@[[t.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:10],[t.topAnchor constraintEqualToAnchor:v.topAnchor constant:8],[x.leadingAnchor constraintEqualToAnchor:t.leadingAnchor],[x.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-8]]];return v;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"";self.view.backgroundColor=NKBG();if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UIScrollView *scroll=[[UIScrollView alloc]init];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.alwaysBounceVertical=YES;scroll.showsVerticalScrollIndicator=NO;
    UIStackView *stack=[[UIStackView alloc]init];stack.translatesAutoresizingMaskIntoConstraints=NO;stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;

    UIView *header=[[UIView alloc]init];[header.heightAnchor constraintEqualToConstant:58].active=YES;
    UILabel *logo=[self nkLabel:@"NK" size:15 weight:UIFontWeightBlack color:UIColor.whiteColor];logo.textAlignment=NSTextAlignmentCenter;logo.backgroundColor=NKPurple();logo.layer.cornerRadius=19;logo.layer.masksToBounds=YES;
    UILabel *brand=[self nkLabel:@"NKTouch" size:20 weight:UIFontWeightBold color:UIColor.whiteColor];UILabel *sub=[self nkLabel:@"Lua automation trên iPhone" size:10.5 weight:UIFontWeightRegular color:NKMuted()];
    UILabel *ver=[self nkLabel:@"7.4.3" size:10 weight:UIFontWeightBold color:UIColor.whiteColor];ver.textAlignment=NSTextAlignmentCenter;ver.backgroundColor=NKC(0x27264B);ver.layer.cornerRadius=10;ver.layer.masksToBounds=YES;
    [header addSubview:logo];[header addSubview:brand];[header addSubview:sub];[header addSubview:ver];
    [NSLayoutConstraint activateConstraints:@[[logo.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],[logo.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],[logo.widthAnchor constraintEqualToConstant:38],[logo.heightAnchor constraintEqualToConstant:38],[brand.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:10],[brand.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],[sub.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],[sub.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:1],[ver.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],[ver.centerYAnchor constraintEqualToAnchor:brand.centerYAnchor],[ver.widthAnchor constraintEqualToConstant:48],[ver.heightAnchor constraintEqualToConstant:21]]];

    NKGradientView *hero=[[NKGradientView alloc]init];hero.translatesAutoresizingMaskIntoConstraints=NO;[hero.heightAnchor constraintEqualToConstant:158].active=YES;
    UILabel *ht=[self nkLabel:@"Lua Studio" size:25 weight:UIFontWeightBold color:UIColor.whiteColor];UILabel *hs=[self nkLabel:@"Viết • Check • Run • Debug\nKhông cần rời NKTouch" size:12 weight:UIFontWeightRegular color:NKC(0xE5DFFF)];hs.numberOfLines=2;
    NKGradientButton *open=[[NKGradientButton alloc]init];open.translatesAutoresizingMaskIntoConstraints=NO;[open setTitle:@"Mở Workspace  ›" forState:UIControlStateNormal];[open addTarget:self action:@selector(openWorkspace) forControlEvents:UIControlEventTouchUpInside];
    UIImageView *code=[[UIImageView alloc]initWithImage:NKIcon(@"chevron.left.forwardslash.chevron.right",39)];code.translatesAutoresizingMaskIntoConstraints=NO;code.tintColor=NKC(0x6FE1FF);code.backgroundColor=[NKC(0x190C53) colorWithAlphaComponent:.55];code.layer.cornerRadius=20;code.contentMode=UIViewContentModeCenter;
    [hero addSubview:ht];[hero addSubview:hs];[hero addSubview:open];[hero addSubview:code];
    [NSLayoutConstraint activateConstraints:@[[ht.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:18],[ht.topAnchor constraintEqualToAnchor:hero.topAnchor constant:22],[hs.leadingAnchor constraintEqualToAnchor:ht.leadingAnchor],[hs.topAnchor constraintEqualToAnchor:ht.bottomAnchor constant:5],[open.leadingAnchor constraintEqualToAnchor:ht.leadingAnchor],[open.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-18],[open.widthAnchor constraintEqualToConstant:148],[open.heightAnchor constraintEqualToConstant:39],[code.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-18],[code.centerYAnchor constraintEqualToAnchor:hero.centerYAnchor],[code.widthAnchor constraintEqualToConstant:82],[code.heightAnchor constraintEqualToConstant:82]]];

    UIView *task=[[UIView alloc]init];task.translatesAutoresizingMaskIntoConstraints=NO;NKCard(task,15);[task.heightAnchor constraintEqualToConstant:82].active=YES;
    UILabel *taskTitle=[self nkLabel:@"Tác vụ hiện tại" size:12 weight:UIFontWeightSemibold color:NKMuted()];self.taskStateLabel=[self nkLabel:@"● Sẵn sàng" size:13 weight:UIFontWeightBold color:NKGreen()];self.taskDetailLabel=[self nkLabel:@"Không có script đang chạy" size:11 weight:UIFontWeightRegular color:NKMuted()];
    [task addSubview:taskTitle];[task addSubview:self.taskStateLabel];[task addSubview:self.taskDetailLabel];
    [NSLayoutConstraint activateConstraints:@[[taskTitle.leadingAnchor constraintEqualToAnchor:task.leadingAnchor constant:14],[taskTitle.topAnchor constraintEqualToAnchor:task.topAnchor constant:11],[self.taskStateLabel.leadingAnchor constraintEqualToAnchor:taskTitle.leadingAnchor],[self.taskStateLabel.topAnchor constraintEqualToAnchor:taskTitle.bottomAnchor constant:7],[self.taskDetailLabel.trailingAnchor constraintEqualToAnchor:task.trailingAnchor constant:-14],[self.taskDetailLabel.centerYAnchor constraintEqualToAnchor:self.taskStateLabel.centerYAnchor]]];

    NKMenuCard *lib=[[NKMenuCard alloc]initWithIcon:@"folder.fill" title:@"Thư viện" subtitle:@"Script Lua của bạn" tint:NKBlue()];
    NKMenuCard *api=[[NKMenuCard alloc]initWithIcon:@"network" title:@"API / HTTP" subtitle:@"HTTP, JSON, Network" tint:NKC(0x58D6FF)];
    NKMenuCard *rec=[[NKMenuCard alloc]initWithIcon:@"record.circle.fill" title:@"Recorder" subtitle:@"Ghi thao tác" tint:NKRed()];
    NKMenuCard *tools=[[NKMenuCard alloc]initWithIcon:@"wrench.and.screwdriver.fill" title:@"Công cụ" subtitle:@"Format, mẫu, tiện ích" tint:NKPurple()];
    [lib addTarget:self action:@selector(openWorkspace) forControlEvents:UIControlEventTouchUpInside];[api addTarget:self action:@selector(openTools) forControlEvents:UIControlEventTouchUpInside];[tools addTarget:self action:@selector(openTools) forControlEvents:UIControlEventTouchUpInside];[rec addTarget:self action:@selector(recordInfo) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *r1=[[UIStackView alloc]initWithArrangedSubviews:@[lib,api]];r1.axis=UILayoutConstraintAxisHorizontal;r1.spacing=10;r1.distribution=UIStackViewDistributionFillEqually;[r1.heightAnchor constraintEqualToConstant:108].active=YES;
    UIStackView *r2=[[UIStackView alloc]initWithArrangedSubviews:@[rec,tools]];r2.axis=UILayoutConstraintAxisHorizontal;r2.spacing=10;r2.distribution=UIStackViewDistributionFillEqually;[r2.heightAnchor constraintEqualToConstant:108].active=YES;

    UIView *health=[[UIView alloc]init];health.translatesAutoresizingMaskIntoConstraints=NO;NKCard(health,15);[health.heightAnchor constraintEqualToConstant:86].active=YES;
    UILabel *healthTitle=[self nkLabel:@"Hệ thống" size:12 weight:UIFontWeightSemibold color:NKMuted()];UIStackView *pills=[[UIStackView alloc]initWithArrangedSubviews:@[[self statusPill:@"ENGINE" value:@"OK" tint:NKGreen()],[self statusPill:@"LUA" value:@"5.4.9" tint:NKGreen()],[self statusPill:@"NETWORK" value:@"OK" tint:NKGreen()]]];pills.translatesAutoresizingMaskIntoConstraints=NO;pills.axis=UILayoutConstraintAxisHorizontal;pills.spacing=8;pills.distribution=UIStackViewDistributionFillEqually;
    [health addSubview:healthTitle];[health addSubview:pills];[NSLayoutConstraint activateConstraints:@[[healthTitle.leadingAnchor constraintEqualToAnchor:health.leadingAnchor constant:14],[healthTitle.topAnchor constraintEqualToAnchor:health.topAnchor constant:10],[pills.leadingAnchor constraintEqualToAnchor:health.leadingAnchor constant:10],[pills.trailingAnchor constraintEqualToAnchor:health.trailingAnchor constant:-10],[pills.topAnchor constraintEqualToAnchor:healthTitle.bottomAnchor constant:7],[pills.bottomAnchor constraintEqualToAnchor:health.bottomAnchor constant:-9]]];

    [stack addArrangedSubview:header];[stack addArrangedSubview:hero];[stack addArrangedSubview:task];[stack addArrangedSubview:r1];[stack addArrangedSubview:r2];[stack addArrangedSubview:health];
    [scroll addSubview:stack];[self.view addSubview:scroll];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:10],[stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:14],[stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-14],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-26]]];
}
- (void)refreshTaskState {
    NSString *running=NKRunningScriptName();
    if(running.length){self.taskStateLabel.text=@"● Đang chạy";self.taskStateLabel.textColor=NKGreen();self.taskDetailLabel.text=running;}
    else{self.taskStateLabel.text=@"● Sẵn sàng";self.taskStateLabel.textColor=NKGreen();self.taskDetailLabel.text=@"Không có script đang chạy";}
}
- (void)openWorkspace { UIViewController *vc=[[NSClassFromString(@"NKLuaLibraryViewController") alloc]init];vc.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:vc animated:YES]; }
- (void)openTools { UIViewController *vc=[[NSClassFromString(@"NKLuaToolsViewController") alloc]init];vc.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:vc animated:YES]; }
- (void)recordInfo { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Recorder V2" message:@"Recorder vẫn dùng engine hiện tại. Bản 7.4.3 chỉ thay luồng giao diện, không thay protocol ghi/chạy." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil]; }
@end

#pragma mark - Library'''
pattern = re.compile(r'#pragma mark - Dashboard\n.*?#pragma mark - Library', re.S)
s, n = pattern.subn(dashboard, s, count=1)
if n != 1:
    raise SystemExit(f"dashboard replacement failed: {n}")

# Force the library's create dialog to stay in the same dark visual system and
# keep the safer validation/collision behavior added in V7.4.1.
new_script = r'''- (void)newScript{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Script mới" message:@"Đặt tên file Lua. Ví dụ: login-test.lua" preferredStyle:UIAlertControllerStyleAlert];
    if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    [a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"script-name.lua";f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;f.clearButtonMode=UITextFieldViewModeWhileEditing;}];__weak typeof(self)w=self;
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Tạo script" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;NSString*n=NKSafeName(a.textFields.firstObject.text?:@"");
        if(!n.length){UIAlertController*e=[UIAlertController alertControllerWithTitle:@"Tên không hợp lệ" message:@"Chỉ dùng chữ, số, dấu chấm, gạch ngang hoặc gạch dưới." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))e.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[e addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];[w presentViewController:e animated:YES completion:nil];return;}
        NSString*p=NKPath(n);if([[NSFileManager defaultManager]fileExistsAtPath:p]){UIAlertController*e=[UIAlertController alertControllerWithTitle:@"Script đã tồn tại" message:n preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))e.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[e addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];[e addAction:[UIAlertAction actionWithTitle:@"Mở script" style:UIAlertActionStyleDefault handler:^(UIAlertAction*y){(void)y;NKLuaEditorViewController*ed=[[NKLuaEditorViewController alloc]initWithScriptName:n];ed.hidesBottomBarWhenPushed=YES;[w.navigationController pushViewController:ed animated:YES];}]];[w presentViewController:e animated:YES completion:nil];return;}
        NSError*err=nil;if(![NKStarter() writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:&err]){return;}[w reloadScripts];NKLuaEditorViewController*ed=[[NKLuaEditorViewController alloc]initWithScriptName:n];ed.hidesBottomBarWhenPushed=YES;[w.navigationController pushViewController:ed animated:YES];
    }]];[self presentViewController:a animated:YES completion:nil];
}'''
pattern = re.compile(r'- \(void\)newScript\{.*?\n\}\n@end\n\n#pragma mark - Editor', re.S)
s, n = pattern.subn(new_script + '\n@end\n\n#pragma mark - Editor', s, count=1)
if n != 1:
    raise SystemExit(f"newScript replacement failed: {n}")

# Make system sheets used by Samples follow the dark shell as well.
s = s.replace('UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Script mẫu" message:@"Tạo file mới rồi mở ngay trong Editor." preferredStyle:UIAlertControllerStyleActionSheet];__weak typeof(self)w=self;', 'UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Script mẫu" message:@"Tạo file mới rồi mở ngay trong Editor." preferredStyle:UIAlertControllerStyleActionSheet];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;__weak typeof(self)w=self;')
s = s.replace('NKTouch v7.4.1', 'NKTouch v7.4.3')
s = s.replace('self.title=@"Lua Workspace";', 'self.title=@"Scripts";', 1)
settings.write_text(s)

# Root shell: the old storyboard's Scripts tab is kept only as a compatibility
# resource. At runtime we replace its root controller with NKTouch Home and keep
# Settings as the second tab. This removes the white legacy Scripts/Create Folder
# route shown in the video without deleting upstream functionality from the app.
scene_text = scene.read_text()
scene_method = r'''- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    (void)session; (void)connectionOptions;
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        for (UIWindow *win in ((UIWindowScene *)scene).windows) win.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        UIViewController *root = self.window.rootViewController;
        if (![root isKindOfClass:[UITabBarController class]]) return;
        UITabBarController *tabs = (UITabBarController *)root;
        tabs.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        tabs.tabBar.tintColor = [UIColor colorWithRed:0.545 green:0.239 blue:1.0 alpha:1.0];
        tabs.tabBar.unselectedItemTintColor = [UIColor colorWithRed:0.50 green:0.55 blue:0.68 alpha:1.0];
        if (@available(iOS 13.0, *)) {
            UITabBarAppearance *appearance = [[UITabBarAppearance alloc] init];
            [appearance configureWithOpaqueBackground];
            appearance.backgroundColor = [UIColor colorWithRed:0.027 green:0.043 blue:0.102 alpha:1.0];
            appearance.shadowColor = [UIColor colorWithRed:0.16 green:0.20 blue:0.33 alpha:1.0];
            tabs.tabBar.standardAppearance = appearance;
            if (@available(iOS 15.0, *)) tabs.tabBar.scrollEdgeAppearance = appearance;
        }
        NSArray<UIViewController *> *controllers = tabs.viewControllers ?: @[];
        if (controllers.count > 0) {
            UIViewController *first = controllers[0];
            if ([first isKindOfClass:[UINavigationController class]]) {
                UINavigationController *nav = (UINavigationController *)first;
                Class homeClass = NSClassFromString(@"NKLuaWorkspaceViewController");
                if (homeClass) {
                    UIViewController *home = [[homeClass alloc] init];
                    [nav setViewControllers:@[home] animated:NO];
                    nav.tabBarItem.title = @"NKTouch";
                    if (@available(iOS 13.0, *)) nav.tabBarItem.image = [UIImage systemImageNamed:@"terminal.fill"];
                }
            }
        }
        if (controllers.count > 1) {
            controllers[1].tabBarItem.title = @"Cài đặt";
            if (@available(iOS 13.0, *)) controllers[1].tabBarItem.image = [UIImage systemImageNamed:@"gearshape.fill"];
        }
        tabs.selectedIndex = 0;
    });
}'''
scene_pattern = re.compile(r'- \(void\)scene:\(UIScene \*\)scene willConnectToSession:.*?\n\}\n\n\n- \(void\)sceneDidDisconnect:', re.S)
scene_text, n = scene_pattern.subn(scene_method + '\n\n\n- (void)sceneDidDisconnect:', scene_text, count=1)
if n != 1:
    raise SystemExit(f"SceneDelegate shell replacement failed: {n}")
scene_text = scene_text.replace('@implementation SceneDelegate\n', '@implementation SceneDelegate\n// V7.4.3 NKTouch root shell: replace legacy Scripts tab at runtime.\n', 1)
scene.write_text(scene_text)

# Regression guards for the exact UX failures observed in the video.
checks = {
    settings: [
        'V7.4.3 shell UX rebuild',
        'self.title = @"Cài đặt"',
        '@"Lua Studio"',
        'vc.hidesBottomBarWhenPushed=YES',
        'a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark',
        'self.title=@"Scripts"',
    ],
    scene: [
        'V7.4.3 NKTouch root shell',
        'NSClassFromString(@"NKLuaWorkspaceViewController")',
        'nav.tabBarItem.title = @"NKTouch"',
        'tabs.selectedIndex = 0',
    ],
}
for path, markers in checks.items():
    text = path.read_text()
    for marker in markers:
        if marker not in text:
            raise SystemExit(f"missing UX regression marker in {path.name}: {marker}")

print("NKTouch v0.7.4.3 shell UX rebuild applied")
