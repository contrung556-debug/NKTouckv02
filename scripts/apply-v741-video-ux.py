#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v741-video-ux.py <NKLuaWorkspace.m.inc>")

p = Path(sys.argv[1])
s = p.read_text()

if "V7.4.1 video UX hotfix" in s:
    print("V7.4.1 video UX hotfix already applied")
    raise SystemExit(0)


def once(old: str, new: str, label: str):
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 marker, found {count}")
    s = s.replace(old, new, 1)


once(
    "// editor/logs/results and script tools. Core runtime remains V7.4.\n",
    "// editor/logs/results and script tools. Core runtime remains V7.4.\n"
    "// V7.4.1 video UX hotfix: direct workspace, real filters/samples/task state.\n",
    "header",
)

helpers = r'''
static NSString * const NKLuaFavoritesKey = @"NKTouch.LuaFavorites.v1";

static NSSet<NSString *> *NKFavoriteSet(void) {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:NKLuaFavoritesKey];
    return [NSSet setWithArray:saved ?: @[]];
}
static BOOL NKIsFavorite(NSString *name) {
    return name.length && [NKFavoriteSet() containsObject:name.lastPathComponent];
}
static void NKToggleFavorite(NSString *name) {
    if (!name.length) return;
    NSMutableSet *set = [NKFavoriteSet() mutableCopy];
    NSString *key = name.lastPathComponent;
    if ([set containsObject:key]) [set removeObject:key]; else [set addObject:key];
    NSArray *saved = [[set allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [[NSUserDefaults standardUserDefaults] setObject:saved forKey:NKLuaFavoritesKey];
}
static NSDate *NKScriptModified(NSString *name) {
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:NKPath(name) error:nil];
    return a[NSFileModificationDate] ?: [NSDate distantPast];
}
static NSDictionary<NSString *,NSString *> *NKParseKV(NSString *text) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        (void)stop;
        NSRange r = [line rangeOfString:@"="];
        if (r.location == NSNotFound || r.location == 0) return;
        NSString *k = [line substringToIndex:r.location];
        NSString *v = [line substringFromIndex:r.location + 1];
        if (k.length) out[k] = v ?: @"";
    }];
    return out;
}
static BOOL NKTaskStateIsActive(NSString *state) {
    NSString *v = state.lowercaseString ?: @"";
    return [@[@"starting", @"running", @"paused", @"stopping"] containsObject:v];
}
static NSString *NKRunningScriptName(void) {
    int code = 0;
    NSDictionary *d = NKParseKV(NKLuaRun(@[@"status"], &code));
    if (code != 0 || !NKTaskStateIsActive(d[@"state"])) return nil;
    return [d[@"script"] lastPathComponent];
}
static NSArray<NSString *> *NKFilterScripts(NSArray<NSString *> *all, NSInteger filter) {
    if (filter == 1) {
        NSString *running = NKRunningScriptName();
        if (!running.length) return @[];
        return [all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
            (void)bindings; return [name.lastPathComponent isEqualToString:running];
        }]];
    }
    if (filter == 2) {
        NSSet *favorites = NKFavoriteSet();
        return [all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
            (void)bindings; return [favorites containsObject:name.lastPathComponent];
        }]];
    }
    if (filter == 3) {
        return [all sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [NKScriptModified(b) compare:NKScriptModified(a)];
        }];
    }
    return all;
}
static NSString *NKUniqueSampleName(NSString *base) {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSInteger i = 1; i < 1000; i++) {
        NSString *name = i == 1 ? [base stringByAppendingString:@".lua"] : [NSString stringWithFormat:@"%@-%ld.lua", base, (long)i];
        if (![fm fileExistsAtPath:NKPath(name)]) return name;
    }
    return [NSString stringWithFormat:@"%@-%lld.lua", base, (long long)NSDate.date.timeIntervalSince1970];
}
static NSString *NKSampleBody(NSString *kind) {
    if ([kind isEqualToString:@"tap"]) return @"-- NKTouch v7.4.1 · Tap sample\nlocal nk = require(\"nktouch_v7\")\n\nassert(nk.tap(120, 450))\nassert(nk.sleep(500))\n";
    if ([kind isEqualToString:@"http"]) return @"-- NKTouch v7.4.1 · HTTP sample\nlocal nk = require(\"nktouch_v7\")\n\nlocal r, err = nk.http.get(\"https://example.com\", {timeout_ms = 5000})\nassert(r, err)\nprint(\"HTTP status\", r.status)\nprint(r.body or \"\")\n";
    return @"-- NKTouch v7.4.1 · Explicit OCR sample\n-- OCR runs only because this script explicitly calls nk.ocr.\nlocal nk = require(\"nktouch_v7\")\n\nlocal text, err = nk.ocr(0, 0, 750, 300, \"en-US\")\nassert(text, err)\nprint(text)\n";
}
'''

once(
    "\n\n@class NKLuaLibraryViewController, NKLuaToolsViewController, NKAIPromptViewController;",
    "\n" + helpers + "\n@class NKLuaLibraryViewController, NKLuaToolsViewController, NKAIPromptViewController;",
    "helpers",
)

old_seg = 'UISegmentedControl *seg=[[UISegmentedControl alloc]initWithItems:@[@"Tất cả",@"Đang chạy",@"Yêu thích",@"Thư mục"]];seg.translatesAutoresizingMaskIntoConstraints=NO;seg.selectedSegmentIndex=0;seg.selectedSegmentTintColor=NKPurple();[seg setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor,NSFontAttributeName:[UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];'
new_seg = 'UISegmentedControl *seg=[[UISegmentedControl alloc]initWithItems:@[@"Tất cả",@"Đang chạy",@"Yêu thích",@"Gần đây"]];seg.translatesAutoresizingMaskIntoConstraints=NO;seg.tag=741;seg.selectedSegmentIndex=0;seg.selectedSegmentTintColor=NKPurple();[seg setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor,NSFontAttributeName:[UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];[seg addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];'
once(old_seg, new_seg, "library segmented control")

old_reload = '- (void)reloadScripts { NSArray *all=NKScripts();NSString *q=self.search.text.lowercaseString?:@"";self.scripts=q.length?[all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *n,NSDictionary *b){(void)b;return[n.lowercaseString containsString:q];}]]:all;[self.table reloadData]; }'
new_reload = '''- (void)reloadScripts {
    NSArray *all=NKScripts();
    UISegmentedControl *seg=(UISegmentedControl *)[self.view viewWithTag:741];
    all=NKFilterScripts(all,seg?seg.selectedSegmentIndex:0);
    NSString *q=self.search.text.lowercaseString?:@"";
    self.scripts=q.length?[all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *n,NSDictionary *b){(void)b;return[n.lowercaseString containsString:q];}]]:all;
    [self.table reloadData];
}
- (void)filterChanged:(UISegmentedControl*)seg{(void)seg;[self reloadScripts];}'''
once(old_reload, new_reload, "library reload")

old_select = '- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{(void)tv;if(ip.row<self.scripts.count){[self.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:self.scripts[ip.row]] animated:YES];}else if(ip.row==self.scripts.count){[self.navigationController pushViewController:[[NSClassFromString(@"NKLuaToolsViewController") alloc]init] animated:YES];}}'
new_select = r'''- (UISwipeActionsConfiguration*)tableView:(UITableView*)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*)ip{
    (void)tv;
    if(ip.row>=self.scripts.count)return nil;
    NSString *name=self.scripts[ip.row];BOOL favorite=NKIsFavorite(name);__weak typeof(self)w=self;
    UIContextualAction *a=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:(favorite?@"Bỏ thích":@"Yêu thích") handler:^(UIContextualAction *action,UIView *source,void(^done)(BOOL)){(void)action;(void)source;NKToggleFavorite(name);[w reloadScripts];done(YES);}];
    a.backgroundColor=favorite?NKPanel2():NKPurple();if(@available(iOS 13.0,*))a.image=NKIcon(favorite?@"star.slash":@"star.fill",16);
    UISwipeActionsConfiguration *c=[UISwipeActionsConfiguration configurationWithActions:@[a]];c.performsFirstActionWithFullSwipe=YES;return c;
}
- (void)createSample:(NSString*)kind base:(NSString*)base{
    NSString *name=NKUniqueSampleName(base);NSError *e=nil;BOOL ok=[NKSampleBody(kind) writeToFile:NKPath(name) atomically:YES encoding:NSUTF8StringEncoding error:&e];
    if(!ok){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Không tạo được mẫu" message:e.localizedDescription?:@"Không thể ghi script." preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}
    [self reloadScripts];NKLuaEditorViewController *editor=[[NKLuaEditorViewController alloc]initWithScriptName:name];editor.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:editor animated:YES];
}
- (void)showSamples{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Script mẫu" message:@"Tạo file mới rồi mở ngay trong Editor." preferredStyle:UIAlertControllerStyleActionSheet];__weak typeof(self)w=self;
    [a addAction:[UIAlertAction actionWithTitle:@"Tap" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w createSample:@"tap" base:@"sample-tap"];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"HTTP / HTTPS" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w createSample:@"http" base:@"sample-http"];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"OCR (chủ động)" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w createSample:@"ocr" base:@"sample-ocr"];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{
    [tv deselectRowAtIndexPath:ip animated:YES];
    if(ip.row<self.scripts.count){NKLuaEditorViewController *editor=[[NKLuaEditorViewController alloc]initWithScriptName:self.scripts[ip.row]];editor.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:editor animated:YES];}
    else if(ip.row==self.scripts.count){UIViewController *tools=[[NSClassFromString(@"NKLuaToolsViewController") alloc]init];tools.hidesBottomBarWhenPushed=YES;[self.navigationController pushViewController:tools animated:YES];}
    else {[self showSamples];}
}'''
once(old_select, new_select, "library selection/samples")

old_new = '- (void)newScript {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Script mới" message:@"Đặt tên file Lua" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"script-name.lua";f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];__weak typeof(self) w=self;[a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Tạo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){(void)x;NSString *n=NKSafeName(a.textFields.firstObject.text?:@"");if(!n.length)return;NSString *p=NKPath(n);if(![[NSFileManager defaultManager]fileExistsAtPath:p])[NKStarter() writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];[w reloadScripts];[w.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:n] animated:YES];}]];[self presentViewController:a animated:YES completion:nil];}'
new_new = r'''- (void)newScript{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Script mới" message:@"Tên chỉ dùng chữ, số, dấu chấm, gạch ngang hoặc gạch dưới." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"script-name.lua";f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];__weak typeof(self)w=self;
    [a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Tạo" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;NSString*n=NKSafeName(a.textFields.firstObject.text?:@"");
        if(!n.length){UIAlertController*e=[UIAlertController alertControllerWithTitle:@"Tên không hợp lệ" message:@"Hãy dùng tên như test-login.lua" preferredStyle:UIAlertControllerStyleAlert];[e addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];[w presentViewController:e animated:YES completion:nil];return;}
        NSString*p=NKPath(n);if([[NSFileManager defaultManager]fileExistsAtPath:p]){UIAlertController*e=[UIAlertController alertControllerWithTitle:@"Script đã tồn tại" message:n preferredStyle:UIAlertControllerStyleAlert];[e addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];[e addAction:[UIAlertAction actionWithTitle:@"Mở" style:UIAlertActionStyleDefault handler:^(UIAlertAction*y){(void)y;NKLuaEditorViewController*ed=[[NKLuaEditorViewController alloc]initWithScriptName:n];ed.hidesBottomBarWhenPushed=YES;[w.navigationController pushViewController:ed animated:YES];}]];[w presentViewController:e animated:YES completion:nil];return;}
        NSError*err=nil;if(![NKStarter() writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:&err])return;[w reloadScripts];NKLuaEditorViewController*ed=[[NKLuaEditorViewController alloc]initWithScriptName:n];ed.hidesBottomBarWhenPushed=YES;[w.navigationController pushViewController:ed animated:YES];
    }]];[self presentViewController:a animated:YES completion:nil];
}'''
once(old_new, new_new, "new script validation")

old_props = '@property(nonatomic,copy) NSString *scriptName;@property(nonatomic,strong) UISegmentedControl *mode;@property(nonatomic,strong) UITextView *codeView;@property(nonatomic,strong) UITextView *console;@property(nonatomic,strong) UIView *editor;@property(nonatomic,strong) UIView *logs;@property(nonatomic,strong) UIView *result;@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,assign) BOOL dirty;'
new_props = '@property(nonatomic,copy) NSString *scriptName;@property(nonatomic,strong) UISegmentedControl *mode;@property(nonatomic,strong) UITextView *codeView;@property(nonatomic,strong) UITextView *console;@property(nonatomic,strong) UIView *editor;@property(nonatomic,strong) UIView *logs;@property(nonatomic,strong) UIView *result;@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UIImageView *syntaxIcon;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,strong) NSTimer *taskTimer;@property(nonatomic,copy) NSString *taskID;@property(nonatomic,assign) BOOL dirty;'
once(old_props, new_props, "editor properties")

once('- (instancetype)initWithScriptName:(NSString*)name{self=[super init];if(self)self.scriptName=name;return self;}', '- (instancetype)initWithScriptName:(NSString*)name{self=[super init];if(self){self.scriptName=name;self.hidesBottomBarWhenPushed=YES;}return self;}', "editor init")

old_icon = 'UIView *syntaxBar=[[UIView alloc]init];syntaxBar.translatesAutoresizingMaskIntoConstraints=NO;NKCard(syntaxBar,10);UIImageView *ok=[[UIImageView alloc]initWithImage:NKIcon(@"checkmark.circle.fill",15)];ok.translatesAutoresizingMaskIntoConstraints=NO;ok.tintColor=NKGreen();self.syntax=[[UILabel alloc]init];self.syntax.translatesAutoresizingMaskIntoConstraints=NO;self.syntax.text=@"Sẵn sàng";self.syntax.textColor=NKGreen();self.syntax.font=[UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];[syntaxBar addSubview:ok];[syntaxBar addSubview:self.syntax];'
new_icon = 'UIView *syntaxBar=[[UIView alloc]init];syntaxBar.translatesAutoresizingMaskIntoConstraints=NO;NKCard(syntaxBar,10);self.syntaxIcon=[[UIImageView alloc]initWithImage:NKIcon(@"circle.dashed",15)];self.syntaxIcon.translatesAutoresizingMaskIntoConstraints=NO;self.syntaxIcon.tintColor=NKMuted();self.syntax=[[UILabel alloc]init];self.syntax.translatesAutoresizingMaskIntoConstraints=NO;self.syntax.text=@"Chưa kiểm tra";self.syntax.textColor=NKMuted();self.syntax.font=[UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];[syntaxBar addSubview:self.syntaxIcon];[syntaxBar addSubview:self.syntax];'
once(old_icon, new_icon, "syntax icon")
s = s.replace('[ok.leadingAnchor constraintEqualToAnchor:syntaxBar.leadingAnchor constant:10],[ok.centerYAnchor constraintEqualToAnchor:syntaxBar.centerYAnchor],[self.syntax.leadingAnchor constraintEqualToAnchor:ok.trailingAnchor constant:5]', '[self.syntaxIcon.leadingAnchor constraintEqualToAnchor:syntaxBar.leadingAnchor constant:10],[self.syntaxIcon.centerYAnchor constraintEqualToAnchor:syntaxBar.centerYAnchor],[self.syntax.leadingAnchor constraintEqualToAnchor:self.syntaxIcon.trailingAnchor constant:5]', 1)

s = s.replace('UIImageView *i=[[UIImageView alloc]initWithImage:NKIcon(@"checkmark.seal.fill",34)];i.translatesAutoresizingMaskIntoConstraints=NO;i.tintColor=NKGreen();', 'UIImageView *i=[[UIImageView alloc]initWithImage:NKIcon(@"checkmark.seal.fill",34)];i.tag=7411;i.translatesAutoresizingMaskIntoConstraints=NO;i.tintColor=NKGreen();', 1)
s = s.replace('UILabel *t=[[UILabel alloc]init];t.translatesAutoresizingMaskIntoConstraints=NO;t.text=@"Kết quả tác vụ";', 'UILabel *t=[[UILabel alloc]init];t.tag=7412;t.translatesAutoresizingMaskIntoConstraints=NO;t.text=@"Kết quả tác vụ";', 1)
s = s.replace('UILabel *s=[[UILabel alloc]init];s.translatesAutoresizingMaskIntoConstraints=NO;s.text=@"Chưa có kết quả. Chạy script để xem trạng thái tại đây.";', 'UILabel *s=[[UILabel alloc]init];s.tag=7413;s.translatesAutoresizingMaskIntoConstraints=NO;s.text=@"Chưa có kết quả. Chạy script để xem trạng thái tại đây.";', 1)

editor_helpers = r'''
- (void)setSyntaxText:(NSString*)text color:(UIColor*)color icon:(NSString*)icon{
    self.syntax.text=text;self.syntax.textColor=color;self.syntaxIcon.tintColor=color;self.syntaxIcon.image=NKIcon(icon,15);
}
- (void)stopTaskPolling{[self.taskTimer invalidate];self.taskTimer=nil;}
- (void)updateResultForState:(NSString*)state info:(NSDictionary*)d{
    UIImageView*i=(UIImageView*)[self.result viewWithTag:7411];UILabel*t=(UILabel*)[self.result viewWithTag:7412];UILabel*detail=(UILabel*)[self.result viewWithTag:7413];
    NSString*v=state.lowercaseString?:@"";NSString*title=@"Kết quả tác vụ";NSString*icon=@"clock.fill";UIColor*color=NKBlue();
    if([v isEqualToString:@"success"]){title=@"Hoàn tất";icon=@"checkmark.seal.fill";color=NKGreen();}
    else if([v isEqualToString:@"failed"]){title=@"Tác vụ lỗi";icon=@"xmark.octagon.fill";color=NKRed();}
    else if([v isEqualToString:@"timeout"]){title=@"Hết thời gian";icon=@"timer";color=NKRed();}
    else if([v isEqualToString:@"stopped"]){title=@"Đã dừng";icon=@"stop.circle.fill";color=NKMuted();}
    else if([v isEqualToString:@"paused"]){title=@"Đã tạm dừng";icon=@"pause.circle.fill";color=NKC(0xFFB545);}
    else if(NKTaskStateIsActive(v)){title=@"Tác vụ đang chạy";icon=@"bolt.circle.fill";color=NKGreen();}
    i.image=NKIcon(icon,34);i.tintColor=color;t.text=title;
    NSString*task=d[@"id"]?:self.taskID?:@"—";NSString*exit=d[@"exit_code"]?:@"—";NSString*script=[d[@"script"] lastPathComponent]?:self.scriptName?:@"—";
    detail.text=[NSString stringWithFormat:@"Script: %@\nTask: %@\nState: %@\nExit: %@",script,task,state.length?state:@"idle",exit];
}
- (void)pollTaskStatus{
    NSString*task=self.taskID;__weak typeof(self)w=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{int code=0;NSMutableArray*args=[NSMutableArray arrayWithObject:@"status"];if(task.length)[args addObject:task];NSString*out=NKLuaRun(args,&code);NSDictionary*d=NKParseKV(out);dispatch_async(dispatch_get_main_queue(),^{
        typeof(self)self=w;if(!self)return;NSString*state=d[@"state"]?:@"idle";NSString*v=state.lowercaseString;
        if(!self.taskID.length&&d[@"id"])self.taskID=d[@"id"];
        if([v isEqualToString:@"starting"]){self.runState.text=@"● Đang khởi động";self.runState.textColor=NKGreen();[self.progress setProgress:.08 animated:YES];}
        else if([v isEqualToString:@"running"]){self.runState.text=@"● Đang chạy";self.runState.textColor=NKGreen();[self.progress setProgress:.45 animated:YES];}
        else if([v isEqualToString:@"paused"]){self.runState.text=@"● Tạm dừng";self.runState.textColor=NKC(0xFFB545);[self.progress setProgress:.45 animated:YES];}
        else if([v isEqualToString:@"stopping"]){self.runState.text=@"● Đang dừng";self.runState.textColor=NKMuted();[self.progress setProgress:.75 animated:YES];}
        else if([v isEqualToString:@"success"]){self.runState.text=@"✓ Hoàn tất";self.runState.textColor=NKGreen();[self.progress setProgress:1 animated:YES];[self stopTaskPolling];}
        else if([v isEqualToString:@"failed"]||[v isEqualToString:@"timeout"]){self.runState.text=[v isEqualToString:@"timeout"]?@"● Hết thời gian":@"● Tác vụ lỗi";self.runState.textColor=NKRed();[self.progress setProgress:0 animated:YES];[self stopTaskPolling];}
        else if([v isEqualToString:@"stopped"]){self.runState.text=@"■ Đã dừng";self.runState.textColor=NKMuted();[self.progress setProgress:0 animated:YES];[self stopTaskPolling];}
        else if([v isEqualToString:@"idle"]&&!self.taskID.length){self.runState.text=@"● Sẵn sàng";self.runState.textColor=NKGreen();}
        [self updateResultForState:state info:d];
        if(!NKTaskStateIsActive(v)&&self.taskID.length){NSString*tid=self.taskID;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{int lc=0;NSString*logs=NKLuaRun(@[@"logs",tid,@"100"],&lc);dispatch_async(dispatch_get_main_queue(),^{if(w&&lc==0)w.console.text=logs;});});}
    });});
}
- (void)startTaskPolling{[self stopTaskPolling];[self pollTaskStatus];self.taskTimer=[NSTimer scheduledTimerWithTimeInterval:.55 target:self selector:@selector(pollTaskStatus) userInfo:nil repeats:YES];[[NSRunLoop mainRunLoop] addTimer:self.taskTimer forMode:NSRunLoopCommonModes];}
'''
once('- (void)modeChanged{self.editor.hidden=self.mode.selectedSegmentIndex!=0;', editor_helpers + '\n- (void)modeChanged{self.editor.hidden=self.mode.selectedSegmentIndex!=0;', "editor task helpers")

once('- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;self.syntax.text=@"Chưa lưu";self.syntax.textColor=NKC(0xFFB545);[self highlight];}', '- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;[self setSyntaxText:@"Chưa kiểm tra" color:NKC(0xFFB545) icon:@"circle.dashed"];[self highlight];}', "dirty syntax state")

once('- (BOOL)save{NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;self.syntax.text=ok?@"Đã lưu":@"Lưu lỗi";self.syntax.textColor=ok?NKGreen():NKRed();return ok;}', '- (BOOL)save{NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;[self setSyntaxText:(ok?@"Đã lưu • Chưa check":@"Lưu lỗi") color:(ok?NKBlue():NKRed()) icon:(ok?@"circle.dashed":@"xmark.circle.fill")];return ok;}', "save syntax state")

once('- (void)checkTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){w.console.text=o;w.syntax.text=c==0?@"Cú pháp hợp lệ":@"Lỗi cú pháp";w.syntax.textColor=c==0?NKGreen():NKRed();if(c!=0){NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];}}];}', '- (void)checkTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){w.console.text=o;[w setSyntaxText:(c==0?@"Cú pháp hợp lệ":@"Lỗi cú pháp") color:(c==0?NKGreen():NKRed()) icon:(c==0?@"checkmark.circle.fill":@"xmark.circle.fill")];if(c!=0){NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];}}];}', "check state")

old_run = '- (void)runTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){if(c!=0){w.console.text=o;w.syntax.text=@"Lỗi cú pháp";w.syntax.textColor=NKRed();NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];return;}[w command:@[@"run",w.scriptName] state:@"● Đang chạy…" done:^(int rc,NSString *ro){w.console.text=ro;w.mode.selectedSegmentIndex=1;[w modeChanged];w.runState.text=rc==0?@"● Đang chạy…":@"● Chạy lỗi";w.runState.textColor=rc==0?NKGreen():NKRed();[w.progress setProgress:rc==0?.18:0 animated:YES];}];}];}'
new_run = '- (void)runTapped{if(![self save])return;self.taskID=nil;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){if(c!=0){w.console.text=o;[w setSyntaxText:@"Lỗi cú pháp" color:NKRed() icon:@"xmark.circle.fill"];NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];return;}[w setSyntaxText:@"Cú pháp hợp lệ" color:NKGreen() icon:@"checkmark.circle.fill"];[w command:@[@"run",w.scriptName] state:@"● Đang khởi động…" done:^(int rc,NSString *ro){w.console.text=ro;if(rc==0){w.taskID=NKParseKV(ro)[@"task_id"];w.mode.selectedSegmentIndex=1;[w modeChanged];[w startTaskPolling];}else{w.runState.text=@"● Chạy lỗi";w.runState.textColor=NKRed();[w.progress setProgress:0 animated:YES];}}];}];}'
once(old_run, new_run, "run state")

once('- (void)stopTapped{__weak typeof(self)w=self;[self command:@[@"stop"] state:@"Đang dừng…" done:^(int c,NSString *o){w.console.text=o;w.runState.text=c==0?@"Đã dừng":@"Dừng lỗi";w.runState.textColor=c==0?NKMuted():NKRed();[w.progress setProgress:0 animated:YES];}];}', '- (void)stopTapped{__weak typeof(self)w=self;NSMutableArray*args=[NSMutableArray arrayWithObject:@"stop"];if(self.taskID.length)[args addObject:self.taskID];[self command:args state:@"Đang dừng…" done:^(int c,NSString *o){w.console.text=o;if(c==0)[w startTaskPolling];else{w.runState.text=@"Dừng lỗi";w.runState.textColor=NKRed();}}];}', "stop state")

once('- (void)logsTapped{__weak typeof(self)w=self;[self command:@[@"logs"] state:@"Đang tải logs…" done:^(int c,NSString *o){w.console.text=o;w.runState.text=c==0?@"● Theo dõi logs":@"Log lỗi";w.runState.textColor=c==0?NKGreen():NKRed();}];}', '- (void)logsTapped{__weak typeof(self)w=self;NSMutableArray*args=[NSMutableArray arrayWithObject:@"logs"];if(self.taskID.length)[args addObject:self.taskID];[args addObject:@"100"];[self command:args state:@"Đang tải logs…" done:^(int c,NSString *o){w.console.text=o;if(c!=0){w.runState.text=@"Log chưa sẵn sàng";w.runState.textColor=NKMuted();}else [w pollTaskStatus];}];}', "logs state")

once('- (void)viewWillDisappear:(BOOL)a{[super viewWillDisappear:a];if(self.dirty)[self save];}', '- (void)viewWillDisappear:(BOOL)a{[self stopTaskPolling];[super viewWillDisappear:a];if(self.dirty)[self save];}', "editor teardown")

p.write_text(s)
print("Applied NKTouch V7.4.1 video UX hotfix")
