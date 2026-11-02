#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: ux-hotfix-v0741.py <input.inc> <output.inc>")

src = Path(sys.argv[1]).read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global src
    count = src.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 match, found {count}")
    src = src.replace(old, new, 1)


# Shared state helpers used by the library and editor.
replace_once(
    'static NSString *NKPath(NSString *name){ return [NKLuaScriptsPath stringByAppendingPathComponent:name?:@""]; }\n'
    'static NSString *NKStarter(void){',
    '''static NSString *NKPath(NSString *name){ return [NKLuaScriptsPath stringByAppendingPathComponent:name?:@""]; }
static NSString *NKActiveScriptName(void){
    NSString *active=[NSString stringWithContentsOfFile:@"/var/mobile/Library/NKTouch/tasks/active" encoding:NSUTF8StringEncoding error:nil];
    active=[active stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!active.length)return nil;
    NSString *statePath=[NSString stringWithFormat:@"/var/mobile/Library/NKTouch/tasks/%@.state",active];
    NSString *state=[NSString stringWithContentsOfFile:statePath encoding:NSUTF8StringEncoding error:nil];
    for(NSString *line in [state componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){
        if([line hasPrefix:@"script="]){NSString *p=[line substringFromIndex:7];return p.lastPathComponent;}
    }
    return nil;
}
static NSSet<NSString*> *NKFavoriteScripts(void){
    NSArray *items=[[NSUserDefaults standardUserDefaults] arrayForKey:@"NKLuaWorkspaceFavorites"]?:@[];
    return [NSSet setWithArray:items];
}
static NSString *NKSampleCode(NSString *kind){
    if([kind isEqualToString:@"tap"])return @"-- NKTouch v7.4.1 • Tap sample\\nlocal nk=require(\\\"nktouch_v7\\\")\\n\\nnk.tap(120,450)\\nnk.sleep(500)\\n";
    if([kind isEqualToString:@"http"])return @"-- NKTouch v7.4.1 • HTTP/JSON sample\\nlocal nk=require(\\\"nktouch_v7\\\")\\n\\nlocal r=assert(nk.http.get(\\\"https://example.com\\\",{timeout_ms=10000}))\\nprint(r.status,r.body)\\n";
    if([kind isEqualToString:@"ocr"])return @"-- NKTouch v7.4.1 • OCR sample\\nlocal nk=require(\\\"nktouch_v7\\\")\\n\\nlocal text=assert(nk.ocr(0,0,750,300,\\\"en-US\\\"))\\nprint(text)\\n";
    return NKStarter();
}
static NSString *NKStarter(void){''',
    "insert workspace helpers",
)

# Library: make the segmented control real instead of decorative.
replace_once(
    '@property(nonatomic,strong) UITableView *table; @property(nonatomic,strong) UISearchBar *search; @property(nonatomic,strong) NSArray<NSString*> *scripts;',
    '@property(nonatomic,strong) UITableView *table; @property(nonatomic,strong) UISearchBar *search; @property(nonatomic,strong) UISegmentedControl *filter; @property(nonatomic,strong) NSArray<NSString*> *scripts;',
    "library filter property",
)
replace_once(
    'UISegmentedControl *seg=[[UISegmentedControl alloc]initWithItems:@[@"Tất cả",@"Đang chạy",@"Yêu thích",@"Thư mục"]];seg.translatesAutoresizingMaskIntoConstraints=NO;seg.selectedSegmentIndex=0;seg.selectedSegmentTintColor=NKPurple();[seg setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor,NSFontAttributeName:[UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];',
    'self.filter=[[UISegmentedControl alloc]initWithItems:@[@"Tất cả",@"Đang chạy",@"Yêu thích",@"Gần đây"]];self.filter.translatesAutoresizingMaskIntoConstraints=NO;self.filter.selectedSegmentIndex=0;self.filter.selectedSegmentTintColor=NKPurple();[self.filter addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];[self.filter setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor,NSFontAttributeName:[UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];',
    "functional library segmented control",
)
replace_once(
    '[self.view addSubview:self.search];[self.view addSubview:seg];[self.view addSubview:self.table];',
    '[self.view addSubview:self.search];[self.view addSubview:self.filter];[self.view addSubview:self.table];',
    "library add filter",
)
src = src.replace('[seg.topAnchor', '[self.filter.topAnchor')
src = src.replace('[seg.leadingAnchor', '[self.filter.leadingAnchor')
src = src.replace('[seg.trailingAnchor', '[self.filter.trailingAnchor')
src = src.replace('[seg.heightAnchor', '[self.filter.heightAnchor')
src = src.replace('constraintEqualToAnchor:seg.bottomAnchor', 'constraintEqualToAnchor:self.filter.bottomAnchor')

replace_once(
    '- (void)reloadScripts { NSArray *all=NKScripts();NSString *q=self.search.text.lowercaseString?:@"";self.scripts=q.length?[all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *n,NSDictionary *b){(void)b;return[n.lowercaseString containsString:q];}]]:all;[self.table reloadData]; }',
    '''- (void)reloadScripts {
    NSArray *all=NKScripts(); NSArray *base=all; NSInteger mode=self.filter?self.filter.selectedSegmentIndex:0;
    if(mode==1){NSString *active=NKActiveScriptName();base=active?[all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *n,NSDictionary *b){(void)b;return[n isEqualToString:active];}]]:@[];}
    else if(mode==2){NSSet *fav=NKFavoriteScripts();base=[all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *n,NSDictionary *b){(void)b;return[fav containsObject:n];}]];}
    else if(mode==3){base=[all sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){NSDate *da=[[[NSFileManager defaultManager]attributesOfItemAtPath:NKPath(a) error:nil]fileModificationDate]?:NSDate.distantPast;NSDate *db=[[[NSFileManager defaultManager]attributesOfItemAtPath:NKPath(b) error:nil]fileModificationDate]?:NSDate.distantPast;return[db compare:da];}];}
    NSString *q=self.search.text.lowercaseString?:@"";
    self.scripts=q.length?[base filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *n,NSDictionary *b){(void)b;return[n.lowercaseString containsString:q];}]]:base;
    [self.table reloadData];
}''',
    "functional library reload",
)
replace_once(
    '- (void)searchBar:(UISearchBar*)s textDidChange:(NSString*)t{(void)s;(void)t;[self reloadScripts];}',
    '- (void)searchBar:(UISearchBar*)s textDidChange:(NSString*)t{(void)s;(void)t;[self reloadScripts];}\n- (void)filterChanged{[self.search resignFirstResponder];[self reloadScripts];}',
    "library filter handler",
)

# Make favorite/running state visible in each row.
replace_once(
    'if(ip.row<self.scripts.count){NSString *n=self.scripts[ip.row];name.text=n;NSDictionary *a=[[NSFileManager defaultManager]attributesOfItemAtPath:NKPath(n) error:nil];meta.text=[NSString stringWithFormat:@"%.1f KB • Lua",MAX(.1,[a fileSize]/1024.0)];}else{BOOL tools=ip.row==self.scripts.count;name.text=tools?@"Tools":@"Samples";meta.text=tools?@"Công cụ Script":@"Ví dụ mẫu";}',
    'if(ip.row<self.scripts.count){NSString *n=self.scripts[ip.row];BOOL fav=[NKFavoriteScripts() containsObject:n];BOOL running=[n isEqualToString:NKActiveScriptName()];name.text=fav?[NSString stringWithFormat:@"★  %@",n]:n;NSDictionary *a=[[NSFileManager defaultManager]attributesOfItemAtPath:NKPath(n) error:nil];meta.text=[NSString stringWithFormat:@"%@%.1f KB • Lua",running?@"● Đang chạy • ":@"",MAX(.1,[a fileSize]/1024.0)];meta.textColor=running?NKGreen():NKMuted();}else{BOOL tools=ip.row==self.scripts.count;name.text=tools?@"Tools":@"Samples";meta.text=tools?@"Công cụ Script":@"Tạo nhanh từ mẫu";}',
    "library row state",
)

# Swipe a script to favorite/unfavorite it.
needle = '- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{'
if src.count(needle) != 1:
    raise SystemExit(f"library didSelect insertion: expected 1 match, found {src.count(needle)}")
swipe = '''- (UISwipeActionsConfiguration*)tableView:(UITableView*)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*)ip{
    (void)tv;if(ip.row>=self.scripts.count)return nil;NSString *name=self.scripts[ip.row];NSMutableArray *fav=[[[NSUserDefaults standardUserDefaults]arrayForKey:@"NKLuaWorkspaceFavorites"]mutableCopy]?:[NSMutableArray array];BOOL exists=[fav containsObject:name];__weak typeof(self)w=self;
    UIContextualAction *star=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:exists?@"Bỏ thích":@"Yêu thích" handler:^(UIContextualAction *a,UIView *v,void(^done)(BOOL)){(void)a;(void)v;if(exists)[fav removeObject:name];else[fav addObject:name];[[NSUserDefaults standardUserDefaults]setObject:fav forKey:@"NKLuaWorkspaceFavorites"];[w reloadScripts];done(YES);}];star.backgroundColor=NKPurple();
    return[UISwipeActionsConfiguration configurationWithActions:@[star]];
}
'''
src = src.replace(needle, swipe + needle, 1)

# Samples row now creates useful runnable examples instead of being a dead row.
replace_once(
    '- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{(void)tv;if(ip.row<self.scripts.count){[self.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:self.scripts[ip.row]] animated:YES];}else if(ip.row==self.scripts.count){[self.navigationController pushViewController:[[NSClassFromString(@"NKLuaToolsViewController") alloc]init] animated:YES];}}',
    '- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{(void)tv;if(ip.row<self.scripts.count){[self.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:self.scripts[ip.row]] animated:YES];}else if(ip.row==self.scripts.count){[self.navigationController pushViewController:[[NSClassFromString(@"NKLuaToolsViewController") alloc]init] animated:YES];}else{[self openSamples];}}',
    "samples row action",
)

needle = '- (void)newScript {'
if src.count(needle) != 1:
    raise SystemExit(f"sample menu insertion: expected 1 match, found {src.count(needle)}")
samples = '''- (void)openSamples{
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"Tạo từ mẫu" message:@"Chọn một mẫu rồi sửa trực tiếp trong Editor." preferredStyle:UIAlertControllerStyleActionSheet];NSArray *items=@[@[@"Tap cơ bản",@"tap",@"sample-tap"],@[@"HTTP / JSON",@"http",@"sample-http"],@[@"OCR",@"ocr",@"sample-ocr"]];__weak typeof(self)w=self;
    for(NSArray *it in items){[sheet addAction:[UIAlertAction actionWithTitle:it[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;NSString *base=it[2];NSString *name=[base stringByAppendingPathExtension:@"lua"];NSInteger i=2;while([[NSFileManager defaultManager]fileExistsAtPath:NKPath(name)]){name=[NSString stringWithFormat:@"%@-%ld.lua",base,(long)i++];}NSError *e=nil;if(![NKSampleCode(it[1]) writeToFile:NKPath(name) atomically:YES encoding:NSUTF8StringEncoding error:&e])return;[w reloadScripts];[w.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:name] animated:YES];}]];}
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];UIPopoverPresentationController *p=sheet.popoverPresentationController;if(p){p.sourceView=self.view;p.sourceRect=CGRectMake(self.view.bounds.size.width/2,80,1,1);}[self presentViewController:sheet animated:YES completion:nil];
}
'''
src = src.replace(needle, samples + needle, 1)

# Safer New Script UX: invalid/duplicate names show feedback rather than silently doing nothing/opening old content.
old_new = '- (void)newScript {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Script mới" message:@"Đặt tên file Lua" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"script-name.lua";f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];__weak typeof(self) w=self;[a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Tạo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){(void)x;NSString *n=NKSafeName(a.textFields.firstObject.text?:@"");if(!n.length)return;NSString *p=NKPath(n);if(![[NSFileManager defaultManager]fileExistsAtPath:p])[NKStarter() writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];[w reloadScripts];[w.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:n] animated:YES];}]];[self presentViewController:a animated:YES completion:nil];}'
new_new = '''- (void)newScript {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Script mới" message:@"Tên ngắn, không dấu cách. .lua sẽ được thêm tự động." preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"my-script.lua";f.clearButtonMode=UITextFieldViewModeWhileEditing;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];__weak typeof(self) w=self;[a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"Tạo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){(void)x;NSString *n=NKSafeName(a.textFields.firstObject.text?:@"");NSString *msg=nil;if(!n.length)msg=@"Tên chỉ dùng chữ, số, dấu chấm, gạch ngang hoặc gạch dưới.";else if([[NSFileManager defaultManager]fileExistsAtPath:NKPath(n)])msg=@"Tên này đã tồn tại. Hãy chọn tên khác.";if(msg){UIAlertController *e=[UIAlertController alertControllerWithTitle:@"Không thể tạo script" message:msg preferredStyle:UIAlertControllerStyleAlert];[e addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[w presentViewController:e animated:YES completion:nil];return;}NSError *err=nil;if(![NKStarter() writeToFile:NKPath(n) atomically:YES encoding:NSUTF8StringEncoding error:&err])return;[w reloadScripts];[w.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:n] animated:YES];}]];[self presentViewController:a animated:YES completion:nil];}'''
replace_once(old_new, new_new, "new script validation")

# Editor properties for truthful syntax state + real task status/result tracking.
replace_once(
    '@property(nonatomic,copy) NSString *scriptName;@property(nonatomic,strong) UISegmentedControl *mode;@property(nonatomic,strong) UITextView *codeView;@property(nonatomic,strong) UITextView *console;@property(nonatomic,strong) UIView *editor;@property(nonatomic,strong) UIView *logs;@property(nonatomic,strong) UIView *result;@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,assign) BOOL dirty;',
    '@property(nonatomic,copy) NSString *scriptName;@property(nonatomic,strong) UISegmentedControl *mode;@property(nonatomic,strong) UITextView *codeView;@property(nonatomic,strong) UITextView *console;@property(nonatomic,strong) UIView *editor;@property(nonatomic,strong) UIView *logs;@property(nonatomic,strong) UIView *result;@property(nonatomic,strong) UIImageView *syntaxIcon;@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,strong) UIImageView *resultIcon;@property(nonatomic,strong) UILabel *resultTitle;@property(nonatomic,strong) UILabel *resultDetail;@property(nonatomic,strong) NSTimer *statusTimer;@property(nonatomic,assign) BOOL dirty;',
    "editor state properties",
)
replace_once(
    'UIImageView *ok=[[UIImageView alloc]initWithImage:NKIcon(@"checkmark.circle.fill",15)];ok.translatesAutoresizingMaskIntoConstraints=NO;ok.tintColor=NKGreen();self.syntax=[[UILabel alloc]init];self.syntax.translatesAutoresizingMaskIntoConstraints=NO;self.syntax.text=@"Sẵn sàng";self.syntax.textColor=NKGreen();',
    'self.syntaxIcon=[[UIImageView alloc]initWithImage:NKIcon(@"circle.fill",10)];self.syntaxIcon.translatesAutoresizingMaskIntoConstraints=NO;self.syntaxIcon.tintColor=NKMuted();self.syntax=[[UILabel alloc]init];self.syntax.translatesAutoresizingMaskIntoConstraints=NO;self.syntax.text=@"Chưa kiểm tra";self.syntax.textColor=NKMuted();',
    "neutral initial syntax state",
)
src = src.replace('[syntaxBar addSubview:ok]', '[syntaxBar addSubview:self.syntaxIcon]', 1)
src = src.replace('[ok.leadingAnchor', '[self.syntaxIcon.leadingAnchor', 1)
src = src.replace('[ok.centerYAnchor', '[self.syntaxIcon.centerYAnchor', 1)
src = src.replace('constraintEqualToAnchor:ok.trailingAnchor', 'constraintEqualToAnchor:self.syntaxIcon.trailingAnchor', 1)

# Dynamic result card instead of the previous static placeholder.
old_result = '- (void)buildResult {self.result=[[UIView alloc]init];self.result.translatesAutoresizingMaskIntoConstraints=NO;UIView *card=[[UIView alloc]init];card.translatesAutoresizingMaskIntoConstraints=NO;NKCard(card,16);UIImageView *i=[[UIImageView alloc]initWithImage:NKIcon(@"checkmark.seal.fill",34)];i.translatesAutoresizingMaskIntoConstraints=NO;i.tintColor=NKGreen();UILabel *t=[[UILabel alloc]init];t.translatesAutoresizingMaskIntoConstraints=NO;t.text=@"Kết quả tác vụ";t.textColor=UIColor.whiteColor;t.font=[UIFont systemFontOfSize:18 weight:UIFontWeightBold];UILabel *s=[[UILabel alloc]init];s.translatesAutoresizingMaskIntoConstraints=NO;s.text=@"Chưa có kết quả. Chạy script để xem trạng thái tại đây.";s.textColor=NKMuted();s.numberOfLines=0;s.font=[UIFont systemFontOfSize:13];[self.result addSubview:card];[card addSubview:i];[card addSubview:t];[card addSubview:s];[NSLayoutConstraint activateConstraints:@[[card.topAnchor constraintEqualToAnchor:self.result.topAnchor],[card.leadingAnchor constraintEqualToAnchor:self.result.leadingAnchor],[card.trailingAnchor constraintEqualToAnchor:self.result.trailingAnchor],[card.heightAnchor constraintEqualToConstant:180],[i.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],[i.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],[t.leadingAnchor constraintEqualToAnchor:i.trailingAnchor constant:12],[t.centerYAnchor constraintEqualToAnchor:i.centerYAnchor],[s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],[s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],[s.topAnchor constraintEqualToAnchor:i.bottomAnchor constant:18]]];}'
new_result = '''- (void)buildResult {self.result=[[UIView alloc]init];self.result.translatesAutoresizingMaskIntoConstraints=NO;UIView *card=[[UIView alloc]init];card.translatesAutoresizingMaskIntoConstraints=NO;NKCard(card,16);self.resultIcon=[[UIImageView alloc]initWithImage:NKIcon(@"clock.fill",32)];self.resultIcon.translatesAutoresizingMaskIntoConstraints=NO;self.resultIcon.tintColor=NKMuted();self.resultTitle=[[UILabel alloc]init];self.resultTitle.translatesAutoresizingMaskIntoConstraints=NO;self.resultTitle.text=@"Chưa có kết quả";self.resultTitle.textColor=UIColor.whiteColor;self.resultTitle.font=[UIFont systemFontOfSize:18 weight:UIFontWeightBold];self.resultDetail=[[UILabel alloc]init];self.resultDetail.translatesAutoresizingMaskIntoConstraints=NO;self.resultDetail.text=@"Chạy script để xem trạng thái thật của Task Engine tại đây.";self.resultDetail.textColor=NKMuted();self.resultDetail.numberOfLines=0;self.resultDetail.font=[UIFont systemFontOfSize:13];[self.result addSubview:card];[card addSubview:self.resultIcon];[card addSubview:self.resultTitle];[card addSubview:self.resultDetail];[NSLayoutConstraint activateConstraints:@[[card.topAnchor constraintEqualToAnchor:self.result.topAnchor],[card.leadingAnchor constraintEqualToAnchor:self.result.leadingAnchor],[card.trailingAnchor constraintEqualToAnchor:self.result.trailingAnchor],[card.heightAnchor constraintEqualToConstant:180],[self.resultIcon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],[self.resultIcon.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],[self.resultTitle.leadingAnchor constraintEqualToAnchor:self.resultIcon.trailingAnchor constant:12],[self.resultTitle.centerYAnchor constraintEqualToAnchor:self.resultIcon.centerYAnchor],[self.resultDetail.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],[self.resultDetail.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],[self.resultDetail.topAnchor constraintEqualToAnchor:self.resultIcon.bottomAnchor constant:18]]];}'''
replace_once(old_result, new_result, "dynamic result card")

replace_once(
    '- (void)modeChanged{self.editor.hidden=self.mode.selectedSegmentIndex!=0;self.logs.hidden=self.mode.selectedSegmentIndex!=1;self.result.hidden=self.mode.selectedSegmentIndex!=2;if(self.mode.selectedSegmentIndex==1)[self logsTapped];}',
    '- (void)modeChanged{self.editor.hidden=self.mode.selectedSegmentIndex!=0;self.logs.hidden=self.mode.selectedSegmentIndex!=1;self.result.hidden=self.mode.selectedSegmentIndex!=2;if(self.mode.selectedSegmentIndex==1)[self logsTapped];if(self.mode.selectedSegmentIndex==2)[self pollTaskStatus];}',
    "result tab refresh",
)
replace_once(
    '- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;self.syntax.text=@"Chưa lưu";self.syntax.textColor=NKC(0xFFB545);[self highlight];}',
    '- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;self.syntax.text=@"Chưa lưu • Chưa kiểm tra";self.syntax.textColor=NKC(0xFFB545);self.syntaxIcon.image=NKIcon(@"circle.fill",10);self.syntaxIcon.tintColor=NKC(0xFFB545);[self highlight];}',
    "dirty syntax state",
)
replace_once(
    '- (BOOL)save{NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;self.syntax.text=ok?@"Đã lưu":@"Lưu lỗi";self.syntax.textColor=ok?NKGreen():NKRed();return ok;}',
    '- (BOOL)save{NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;self.syntax.text=ok?@"Đã lưu • Chưa kiểm tra":@"Lưu lỗi";self.syntax.textColor=ok?NKMuted():NKRed();self.syntaxIcon.image=NKIcon(ok?@"circle.fill":@"xmark.circle.fill",ok?10:15);self.syntaxIcon.tintColor=ok?NKMuted():NKRed();return ok;}',
    "saved syntax state",
)

# Real task state polling. It stops automatically on terminal states and updates the Result tab.
needle = '- (NSInteger)line:(NSString*)o{'
if src.count(needle) != 1:
    raise SystemExit(f"task polling insertion: expected 1 match, found {src.count(needle)}")
polling = '''- (NSDictionary*)taskFields:(NSString*)text{NSMutableDictionary *d=[NSMutableDictionary dictionary];for(NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){NSRange r=[line rangeOfString:@"="];if(r.location==NSNotFound)continue;NSString *k=[line substringToIndex:r.location];NSString *v=[line substringFromIndex:r.location+1];if(k.length)d[k]=v?:@"";}return d;}
- (void)applyTaskFields:(NSDictionary*)d{NSString *state=d[@"state"]?:@"idle";BOOL terminal=[@[@"success",@"failed",@"stopped",@"timeout"]containsObject:state];if([state isEqualToString:@"running"]||[state isEqualToString:@"starting"]){self.runState.text=@"● Đang chạy";self.runState.textColor=NKGreen();[self.progress setProgress:.45 animated:YES];self.resultTitle.text=@"Đang chạy";self.resultDetail.text=@"Task Engine đang thực thi script. Logs có thể xem theo thời gian thực.";self.resultIcon.image=NKIcon(@"play.circle.fill",32);self.resultIcon.tintColor=NKGreen();}else if([state isEqualToString:@"paused"]){self.runState.text=@"● Tạm dừng";self.runState.textColor=NKC(0xFFB545);self.resultTitle.text=@"Tạm dừng";self.resultDetail.text=@"Task vẫn còn hiệu lực và có thể tiếp tục.";self.resultIcon.image=NKIcon(@"pause.circle.fill",32);self.resultIcon.tintColor=NKC(0xFFB545);}else if(terminal){NSString *exitCode=d[@"exit_code"]?:@"";if([state isEqualToString:@"success"]){self.runState.text=@"● Hoàn thành";self.runState.textColor=NKGreen();self.resultTitle.text=@"Hoàn thành";self.resultDetail.text=[NSString stringWithFormat:@"%@ đã chạy xong thành công.",self.scriptName];self.resultIcon.image=NKIcon(@"checkmark.seal.fill",32);self.resultIcon.tintColor=NKGreen();[self.progress setProgress:1 animated:YES];}else{self.runState.text=[NSString stringWithFormat:@"● %@",[state isEqualToString:@"stopped"]?@"Đã dừng":[state isEqualToString:@"timeout"]?@"Hết thời gian":@"Chạy lỗi"];self.runState.textColor=[state isEqualToString:@"stopped"]?NKMuted():NKRed();self.resultTitle.text=[state isEqualToString:@"stopped"]?@"Đã dừng":[state isEqualToString:@"timeout"]?@"Hết thời gian":@"Chạy lỗi";self.resultDetail.text=exitCode.length?[NSString stringWithFormat:@"Task kết thúc với exit code %@. Mở Logs để xem chi tiết.",exitCode]:@"Mở Logs để xem chi tiết.";self.resultIcon.image=NKIcon([state isEqualToString:@"stopped"]?@"stop.circle.fill":@"xmark.octagon.fill",32);self.resultIcon.tintColor=[state isEqualToString:@"stopped"]?NKMuted():NKRed();[self.progress setProgress:0 animated:YES];}[self.statusTimer invalidate];self.statusTimer=nil;}else{self.runState.text=@"● Sẵn sàng";self.runState.textColor=NKMuted();}}
- (void)pollTaskStatus{dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{int code=0;NSString *out=NKLuaRun(@[@"status"],&code);dispatch_async(dispatch_get_main_queue(),^{if(code==0)[self applyTaskFields:[self taskFields:out?:@""]];});});}
- (void)startStatusPolling{[self.statusTimer invalidate];self.statusTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(pollTaskStatus) userInfo:nil repeats:YES];[self pollTaskStatus];}
'''
src = src.replace(needle, polling + needle, 1)

replace_once(
    '- (void)checkTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){w.console.text=o;w.syntax.text=c==0?@"Cú pháp hợp lệ":@"Lỗi cú pháp";w.syntax.textColor=c==0?NKGreen():NKRed();if(c!=0){NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];}}];}',
    '- (void)checkTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){w.console.text=o;w.syntax.text=c==0?@"Cú pháp hợp lệ":@"Lỗi cú pháp";w.syntax.textColor=c==0?NKGreen():NKRed();w.syntaxIcon.image=NKIcon(c==0?@"checkmark.circle.fill":@"xmark.circle.fill",15);w.syntaxIcon.tintColor=c==0?NKGreen():NKRed();if(c!=0){NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];}}];}',
    "truthful syntax icon",
)
replace_once(
    '- (void)runTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){if(c!=0){w.console.text=o;w.syntax.text=@"Lỗi cú pháp";w.syntax.textColor=NKRed();NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];return;}[w command:@[@"run",w.scriptName] state:@"● Đang chạy…" done:^(int rc,NSString *ro){w.console.text=ro;w.mode.selectedSegmentIndex=1;[w modeChanged];w.runState.text=rc==0?@"● Đang chạy…":@"● Chạy lỗi";w.runState.textColor=rc==0?NKGreen():NKRed();[w.progress setProgress:rc==0?.18:0 animated:YES];}];}];}',
    '- (void)runTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){if(c!=0){w.console.text=o;w.syntax.text=@"Lỗi cú pháp";w.syntax.textColor=NKRed();w.syntaxIcon.image=NKIcon(@"xmark.circle.fill",15);w.syntaxIcon.tintColor=NKRed();NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];return;}w.syntax.text=@"Cú pháp hợp lệ";w.syntax.textColor=NKGreen();w.syntaxIcon.image=NKIcon(@"checkmark.circle.fill",15);w.syntaxIcon.tintColor=NKGreen();[w command:@[@"run",w.scriptName] state:@"● Đang khởi chạy…" done:^(int rc,NSString *ro){w.console.text=ro;if(rc==0){w.mode.selectedSegmentIndex=1;[w modeChanged];[w startStatusPolling];}else{w.runState.text=@"● Chạy lỗi";w.runState.textColor=NKRed();}}];}];}',
    "run with real status polling",
)
replace_once(
    '- (void)stopTapped{__weak typeof(self)w=self;[self command:@[@"stop"] state:@"Đang dừng…" done:^(int c,NSString *o){w.console.text=o;w.runState.text=c==0?@"Đã dừng":@"Dừng lỗi";w.runState.textColor=c==0?NKMuted():NKRed();[w.progress setProgress:0 animated:YES];}];}',
    '- (void)stopTapped{__weak typeof(self)w=self;[self command:@[@"stop"] state:@"Đang dừng…" done:^(int c,NSString *o){w.console.text=o;if(c==0)[w pollTaskStatus];else{w.runState.text=@"Dừng lỗi";w.runState.textColor=NKRed();}}];}',
    "stop refresh",
)
replace_once(
    '- (void)viewWillDisappear:(BOOL)a{[super viewWillDisappear:a];if(self.dirty)[self save];}',
    '- (void)viewWillAppear:(BOOL)a{[super viewWillAppear:a];[self pollTaskStatus];}\n- (void)viewWillDisappear:(BOOL)a{[super viewWillDisappear:a];if(self.dirty)[self save];}\n- (void)viewDidDisappear:(BOOL)a{[super viewDidDisappear:a];[self.statusTimer invalidate];self.statusTimer=nil;}',
    "editor timer lifecycle",
)

Path(sys.argv[2]).write_text(src)
print("V7.4.1 UX hotfix applied")
