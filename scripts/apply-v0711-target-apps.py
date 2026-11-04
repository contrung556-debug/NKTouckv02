#!/usr/bin/env python3
"""NKTouch 0.7.11 target-app chooser + worker-first launch, on staged v0.7.10 source.
The Lua task starts before switching applications so iOS suspending the NKTouch UI
cannot strand a pending run on its main thread.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v0711-target-apps.py <staged-upstream>")
settings=Path(sys.argv[1])/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
s=settings.read_text()
marker="NKTouch v0.7.11 Target Apps"
if marker in s:
    raise SystemExit("target apps already applied")
anchor="#pragma mark - Editor\n"
if s.count(anchor)!=1: raise SystemExit("editor insertion anchor missing")
helpers=r'''
// NKTouch v0.7.11 Target Apps -- configured by the user, one app per Lua script.
#import <objc/message.h>

static NSString * const NKTargetAppsPath=@"/var/mobile/Library/NKTouch/target_apps.plist";
static BOOL NKTargetValidID(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length<3 || s.length>255 || [s isEqualToString:@"com.zjx.zxtouch"]) return NO;
    NSMutableCharacterSet *valid=[[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [valid addCharactersInString:@".-_"];
    return [s containsString:@"."] && [s rangeOfCharacterFromSet:valid.invertedSet].location==NSNotFound;
}
static NSDictionary *NKTargetForScript(NSString *script) {
    NSDictionary *all=[NSDictionary dictionaryWithContentsOfFile:NKTargetAppsPath];
    id entry=[all isKindOfClass:NSDictionary.class]?all[script.lastPathComponent]:nil;
    if (![entry isKindOfClass:NSDictionary.class] || !NKTargetValidID(entry[@"bundle"])) return nil;
    return entry;
}
static BOOL NKSaveTarget(NSString *script, NSString *bundle, NSString *name) {
    if (!script.length || (bundle.length && !NKTargetValidID(bundle))) return NO;
    NSMutableDictionary *all=[([NSDictionary dictionaryWithContentsOfFile:NKTargetAppsPath]?:@{}) mutableCopy];
    if(bundle.length) all[script.lastPathComponent]=@{@"bundle":bundle,@"name":name.length?name:bundle};
    else [all removeObjectForKey:script.lastPathComponent];
    NSString *dir=[NKTargetAppsPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [all writeToFile:NKTargetAppsPath atomically:YES];
}
static id NKTargetCall(id object, NSString *selectorName) {
    SEL selector=NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(object,selector);
}
static NSArray<NSDictionary *> *NKInstalledTargetApps(void) {
    Class c=NSClassFromString(@"LSApplicationWorkspace");
    id workspace=NKTargetCall(c,@"defaultWorkspace");
    id apps=NKTargetCall(workspace,@"allApplications");
    if (![apps isKindOfClass:NSArray.class]) return @[];
    NSMutableDictionary<NSString *,NSDictionary *> *unique=[NSMutableDictionary dictionary];
    for (id proxy in apps) {
        NSString *bundle=NKTargetCall(proxy,@"applicationIdentifier");
        if (!NKTargetValidID(bundle)) continue;
        NSString *name=NKTargetCall(proxy,@"localizedName");
        if (![name isKindOfClass:NSString.class] || !name.length) name=bundle;
        unique[bundle]=@{@"bundle":bundle,@"name":name};
    }
    return [[unique allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
}
static NSString *NKLuaQuoted(NSString *s) {
    NSMutableString *v=[NSMutableString stringWithString:s?:@""];
    [v replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0,v.length)];
    [v replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0,v.length)];
    [v replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0,v.length)];
    [v replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0,v.length)];
    return [NSString stringWithFormat:@"\"%@\"",v];
}

@interface NKTargetAppPickerViewController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic,copy) NSString *script;
@property(nonatomic,copy) void (^selected)(void);
@property(nonatomic,strong) NSArray<NSDictionary *> *apps;
@property(nonatomic,strong) NSArray<NSDictionary *> *filtered;
@property(nonatomic,strong) UISearchController *search;
@end
@implementation NKTargetAppPickerViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Ứng dụng đích"; self.view.backgroundColor=NKBG();
    self.apps=NKInstalledTargetApps(); self.filtered=self.apps;
    self.search=[[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater=self;self.search.obscuresBackgroundDuringPresentation=NO;
    self.search.searchBar.placeholder=@"Tìm theo tên hoặc Bundle ID";
    self.navigationItem.searchController=self.search;self.definesPresentationContext=YES;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addByID)];
    self.tableView.rowHeight=65;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *q=controller.searchBar.text.lowercaseString?:@"";
    self.filtered=q.length?[self.apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item,NSDictionary *bindings){
        (void)bindings;return [item[@"name"] localizedCaseInsensitiveContainsString:q] || [item[@"bundle"] localizedCaseInsensitiveContainsString:q];
    }]]:self.apps;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table;(void)section;return self.filtered.count+1;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    cell.backgroundColor=NKBG();cell.textLabel.textColor=UIColor.whiteColor;
    cell.detailTextLabel.textColor=NKMuted();cell.imageView.image=NKIcon(@"app.fill",22);
    if(index.row==0) {
        cell.textLabel.text=@"Không chọn ứng dụng";cell.detailTextLabel.text=@"Xoá ứng dụng đích của script";
        cell.accessoryType=NKTargetForScript(self.script)?UITableViewCellAccessoryNone:UITableViewCellAccessoryCheckmark;
    } else {
        NSDictionary *a=self.filtered[index.row-1];
        cell.textLabel.text=a[@"name"];cell.detailTextLabel.text=a[@"bundle"];
        cell.accessoryType=[a[@"bundle"] isEqual:NKTargetForScript(self.script)[@"bundle"]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    }
    return cell;
}
- (void)selectBundle:(NSString *)bundle name:(NSString *)name {
    if(!NKSaveTarget(self.script,bundle,name)) {
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Không lưu được" message:@"Không thể lưu ứng dụng đích." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];return;
    }
    if(self.selected)self.selected();
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if(index.row==0){[self selectBundle:nil name:nil];return;}
    NSDictionary *a=self.filtered[index.row-1];
    [self selectBundle:a[@"bundle"] name:a[@"name"]];
}
- (void)addByID {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Thêm bằng Bundle ID" message:@"Dành cho ứng dụng không xuất hiện trong danh sách. Ví dụ: com.apple.mobilesafari" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=@"com.example.app";field.autocapitalizationType=UITextAutocapitalizationTypeNone;field.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [a addAction:[UIAlertAction actionWithTitle:@"Thêm" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        (void)action;NSString *bundle=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(NKTargetValidID(bundle)) [weakSelf selectBundle:bundle name:bundle];
        else {
            UIAlertController *invalid=[UIAlertController alertControllerWithTitle:@"Bundle ID không hợp lệ" message:@"Kiểm tra lại định danh ứng dụng." preferredStyle:UIAlertControllerStyleAlert];
            [invalid addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [weakSelf presentViewController:invalid animated:YES completion:nil];
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

'''
s=s.replace(anchor,helpers+anchor,1)
# Keep NKLuaRun single process-spawn implementation; route target-run to nktask
# without changing any existing nkeditor Check/Run/Logs protocol.
start=s.index("static NSString *NKLuaRun(")
end=s.index("static NSArray<NSString *> *NKScripts(",start)
fn=s[start:end]
old="    NSUInteger argc = arguments.count + 2;\n"
new='''    BOOL targetRun=arguments.count==2 && [arguments[0] isEqualToString:@"target-run"];
    NSArray<NSString *> *effective=targetRun?@[@"start",arguments[1]]:arguments;
    NSString *executable=targetRun?@"/var/jb/usr/bin/nktask":NKLuaEditorTool;
    NSUInteger argc = effective.count + 2;
'''
assert fn.count(old)==1, "NKLuaRun argc marker missing"
fn=fn.replace(old,new,1)
assert fn.count("argv[0] = strdup(NKLuaEditorTool.UTF8String);")==1
fn=fn.replace("argv[0] = strdup(NKLuaEditorTool.UTF8String);","argv[0] = strdup(executable.UTF8String);")
fn=fn.replace("arguments.count","effective.count").replace("arguments[i+1]","effective[i+1]").replace("arguments[i]","effective[i]")
# Correct references modified by generic replacement in the initial routing declaration.
fn=fn.replace("BOOL targetRun=effective.count==2","BOOL targetRun=arguments.count==2")
fn=fn.replace("posix_spawn(&pid, NKLuaEditorTool.UTF8String,","posix_spawn(&pid, executable.UTF8String,")
s=s[:start]+fn+s[end:]
init='[super viewDidLoad];self.title=self.scriptName;self.view.backgroundColor=NKBG();'
assert s.count(init)==1, "editor viewDidLoad marker missing"
s=s.replace(init,init+'self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Ứng dụng +" style:UIBarButtonItemStylePlain target:self action:@selector(nkSelectTargetApp)];[self nkRefreshTargetButton];',1)
# Modify only the editor's successful syntax-check branch.
needle='[w command:@[@"run",w.scriptName]'
assert s.count(needle)==1,"editor task-run marker missing"
s=s.replace(needle,'NSString *wrapper=[w nkTargetWrapper];if(!wrapper){[w nkSelectTargetApp];return;}[w command:@[@"target-run",wrapper]',1)
method_marker='- (void)runTapped{'
assert s.count(method_marker)==1,"editor runTapped marker missing"
methods=r'''
- (void)nkRefreshTargetButton {
    NSDictionary *app=NKTargetForScript(self.scriptName);
    NSString *label=app[@"name"];
    if(label.length>18)label=[[label substringToIndex:15] stringByAppendingString:@"…"];
    self.navigationItem.rightBarButtonItem.title=label.length?[NSString stringWithFormat:@"%@ ▾",label]:@"Ứng dụng +";
}
- (void)nkSelectTargetApp {
    [self.view endEditing:YES];
    NKTargetAppPickerViewController *picker=[NKTargetAppPickerViewController new];
    picker.script=self.scriptName;
    __weak typeof(self) weakSelf=self;
    picker.selected=^{[weakSelf nkRefreshTargetButton];};
    [self.navigationController pushViewController:picker animated:YES];
}
- (NSString *)nkTargetWrapper {
    NSDictionary *app=NKTargetForScript(self.scriptName);
    NSString *bundle=app[@"bundle"];
    if(!NKTargetValidID(bundle))return nil;
    NSString *base=@"/var/mobile/Library/NKTouch/tmp/targets";
    NSError *err=nil;
    if(![[NSFileManager defaultManager]createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:&err])return nil;
    NSString *file=[base stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.lua",NSUUID.UUID.UUIDString]];
    NSString *script=NKPath(self.scriptName);
    NSString *lua=[NSString stringWithFormat:
      @"-- NKTouch Target App bootstrap v0.7.11\n"
       @"local nk=require('nktouch')\n"
       @"os.remove(%@)\n"
       @"local ok,err,code=nk.openApp(%@)\n"
       @"assert(ok, 'TARGET_OPEN_FAILED: '..tostring(code)..' '..tostring(err))\n"
       @"local ready,why,whyCode=nk.waitApp(%@,8000,200)\n"
       @"assert(ready, 'TARGET_NOT_FOREGROUND: '..tostring(whyCode)..' '..tostring(why))\n"
       @"local run=assert(loadfile(%@,'t'))\n"
       @"return run()\n",NKLuaQuoted(file),NKLuaQuoted(bundle),NKLuaQuoted(bundle),NKLuaQuoted(script)];
    if(![lua writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&err])return nil;
    return file;
}
'''
s=s.replace(method_marker,methods+method_marker,1)
settings.write_text(s)
assert 'target-run' in s and 'TARGET_NOT_FOREGROUND' in s and 'NKTargetAppPickerViewController' in s
print("NKTouch 0.7.11 Target Apps staged; task starts before foreground switch")
