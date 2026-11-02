#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: apply-v0753-editor-pro.py <upstream-dir>')

root = Path(sys.argv[1])
settings = root / 'zxtouch/zxtouch/Settings/SettingsPageViewController.m'
if not settings.exists():
    raise SystemExit('missing SettingsPageViewController.m')

s = settings.read_text()
if 'V0.7.5.3 Editor Pro' in s:
    print('Editor Pro already applied')
    raise SystemExit(0)

anchor = '// V0.7.5.2 Recorder V3: native record/pause/resume/timeline editor/test/render UI.\n'
marker = '// V0.7.5.3 Editor Pro: line numbers, find/replace, API snippets, autosave + rolling backups.\n'
if anchor in s:
    s = s.replace(anchor, anchor + marker, 1)
else:
    s = marker + s

s = s.replace('NKTouch 0.7.5.2', 'NKTouch 0.7.5.3')
s = s.replace('nkLabel:@"0.7.5.2"', 'nkLabel:@"0.7.5.3"')
s = s.replace('text:@"0.7.5.2"', 'text:@"0.7.5.3"')

old_props = '@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,assign) BOOL dirty;'
new_props = '@property(nonatomic,strong) UILabel *syntax;@property(nonatomic,strong) UILabel *runState;@property(nonatomic,strong) UIProgressView *progress;@property(nonatomic,assign) BOOL dirty;@property(nonatomic,strong) UITextView *lineNumbers;@property(nonatomic,strong) NSTimer *autosaveTimer;@property(nonatomic,assign) NSTimeInterval lastBackupAt;'
if old_props not in s:
    raise SystemExit('editor property marker missing')
s = s.replace(old_props, new_props, 1)

old_tail = 'self.logs.hidden=YES;self.result.hidden=YES;self.codeView.text=[NSString stringWithContentsOfFile:NKPath(self.scriptName) encoding:NSUTF8StringEncoding error:nil]?:NKStarter();[self highlight];\n}'
new_tail = 'self.logs.hidden=YES;self.result.hidden=YES;self.codeView.text=[NSString stringWithContentsOfFile:NKPath(self.scriptName) encoding:NSUTF8StringEncoding error:nil]?:NKStarter();[self highlight];[self setupEditorPro];\n}'
if old_tail not in s:
    raise SystemExit('editor viewDidLoad tail missing')
s = s.replace(old_tail, new_tail, 1)

old_mode_prefix = '- (void)modeChanged{self.navigationItem.rightBarButtonItem=(self.mode.selectedSegmentIndex==1?[[UIBarButtonItem alloc]initWithTitle:@"Copy Log" style:UIBarButtonItemStylePlain target:self action:@selector(copyCurrentLog)]:nil);self.editor.hidden=self.mode.selectedSegmentIndex!=0;'
new_mode_prefix = '- (void)modeChanged{[self updateEditorProNav];self.editor.hidden=self.mode.selectedSegmentIndex!=0;'
if old_mode_prefix not in s:
    raise SystemExit('daily-driver modeChanged marker missing')
s = s.replace(old_mode_prefix, new_mode_prefix, 1)

old_change = '- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;self.syntax.text=@"Chưa lưu";self.syntax.textColor=NKC(0xFFB545);[self highlight];}'
new_change = '- (void)textViewDidChange:(UITextView*)t{if(t!=self.codeView)return;self.dirty=YES;self.syntax.text=@"Đang chỉnh sửa…";self.syntax.textColor=NKC(0xFFB545);[self highlight];[self updateLineNumbers];[self scheduleAutosave];}'
if old_change not in s:
    raise SystemExit('textViewDidChange marker missing')
s = s.replace(old_change, new_change, 1)

old_save = '- (BOOL)save{NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;self.syntax.text=ok?@"Đã lưu":@"Lưu lỗi";self.syntax.textColor=ok?NKGreen():NKRed();return ok;}'
new_save = '- (BOOL)save{[self backupCurrentIfNeeded];NSError *e=nil;BOOL ok=[self.codeView.text writeToFile:NKPath(self.scriptName) atomically:YES encoding:NSUTF8StringEncoding error:&e];self.dirty=!ok;self.syntax.text=ok?@"Đã lưu":@"Lưu lỗi";self.syntax.textColor=ok?NKGreen():NKRed();return ok;}'
if old_save not in s:
    raise SystemExit('save marker missing')
s = s.replace(old_save, new_save, 1)

editor_pro = r'''
- (void)setupEditorPro{
    self.lineNumbers=[[UITextView alloc]init];self.lineNumbers.editable=NO;self.lineNumbers.selectable=NO;self.lineNumbers.scrollEnabled=NO;self.lineNumbers.userInteractionEnabled=NO;self.lineNumbers.backgroundColor=NKC(0x080D19);self.lineNumbers.textColor=NKC(0x65708D);self.lineNumbers.font=[UIFont monospacedSystemFontOfSize:13.2 weight:UIFontWeightRegular];self.lineNumbers.textAlignment=NSTextAlignmentRight;self.lineNumbers.textContainerInset=UIEdgeInsetsMake(12,2,12,4);self.lineNumbers.textContainer.lineFragmentPadding=0;self.lineNumbers.layer.cornerRadius=11;self.lineNumbers.clipsToBounds=YES;[self.editor addSubview:self.lineNumbers];
    UIEdgeInsets inset=self.codeView.textContainerInset;inset.left=48;self.codeView.textContainerInset=inset;
    UIToolbar *bar=[[UIToolbar alloc]initWithFrame:CGRectMake(0,0,320,40)];bar.barStyle=UIBarStyleBlack;bar.translucent=YES;UIBarButtonItem *flex=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];NSArray *defs=@[@[@"tap",NSStringFromSelector(@selector(insertTapSnippet))],@[@"sleep",NSStringFromSelector(@selector(insertSleepSnippet))],@[@"swipe",NSStringFromSelector(@selector(insertSwipeSnippet))],@[@"text",NSStringFromSelector(@selector(insertTextSnippet))],@[@"HTTP",NSStringFromSelector(@selector(insertHTTPSnippet))]];NSMutableArray *items=[NSMutableArray array];for(NSUInteger i=0;i<defs.count;i++){SEL sel=NSSelectorFromString(defs[i][1]);UIBarButtonItem *it=[[UIBarButtonItem alloc]initWithTitle:defs[i][0] style:UIBarButtonItemStylePlain target:self action:sel];[items addObject:it];if(i+1<defs.count)[items addObject:flex];}bar.items=items;self.codeView.inputAccessoryView=bar;
    [self updateLineNumbers];[self updateEditorProNav];
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];if(self.lineNumbers&&self.editor&&!self.editor.hidden){CGRect f=self.codeView.frame;self.lineNumbers.frame=CGRectMake(CGRectGetMinX(f)+1,CGRectGetMinY(f)+1,40,MAX(0,CGRectGetHeight(f)-2));self.lineNumbers.contentOffset=CGPointMake(0,self.codeView.contentOffset.y);[self.editor bringSubviewToFront:self.lineNumbers];}}
- (void)scrollViewDidScroll:(UIScrollView*)scrollView{if(scrollView==self.codeView&&self.lineNumbers)self.lineNumbers.contentOffset=CGPointMake(0,scrollView.contentOffset.y);}
- (void)updateLineNumbers{if(!self.lineNumbers)return;NSUInteger count=MAX((NSUInteger)1,[[self.codeView.text?:@"" componentsSeparatedByString:@"\n"]count]);NSMutableString *n=[NSMutableString string];for(NSUInteger i=1;i<=count;i++){[n appendFormat:@"%lu",(unsigned long)i];if(i<count)[n appendString:@"\n"];}self.lineNumbers.text=n;self.lineNumbers.contentOffset=CGPointMake(0,self.codeView.contentOffset.y);}
- (void)updateEditorProNav{NSInteger m=self.mode.selectedSegmentIndex;if(m==0){self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Editor ▾" style:UIBarButtonItemStylePlain target:self action:@selector(editorProMenu)];}else if(m==1){self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"Copy Log" style:UIBarButtonItemStylePlain target:self action:@selector(copyCurrentLog)];}else self.navigationItem.rightBarButtonItem=nil;}
- (void)editorProMenu{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Editor Pro" message:@"Công cụ cho script hiện tại" preferredStyle:UIAlertControllerStyleActionSheet];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;__weak typeof(self)w=self;[a addAction:[UIAlertAction actionWithTitle:@"Tìm / Thay thế" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w showFindReplace];}]],[a addAction:[UIAlertAction actionWithTitle:@"Chèn Snippet" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w showSnippetMenu];}]],[a addAction:[UIAlertAction actionWithTitle:@"Khôi phục Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w showBackupMenu];}]],[a addAction:[UIAlertAction actionWithTitle:@"Lưu ngay" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w autosaveNow];}]],[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)showFindReplace{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Tìm / Thay thế" message:@"Tìm tiếp từ vị trí con trỏ hoặc thay toàn bộ." preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"Tìm";f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"Thay bằng (có thể để trống)";f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];__weak typeof(self)w=self;[a addAction:[UIAlertAction actionWithTitle:@"Tìm tiếp" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w findNext:a.textFields.firstObject.text?:@""];}]];[a addAction:[UIAlertAction actionWithTitle:@"Thay tất cả" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w replaceAll:a.textFields.firstObject.text?:@"" with:a.textFields.lastObject.text?:@""];}]];[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)findNext:(NSString*)needle{if(!needle.length)return;NSString *text=self.codeView.text?:@"";NSUInteger start=MIN(NSMaxRange(self.codeView.selectedRange),text.length);NSRange r=[text rangeOfString:needle options:NSCaseInsensitiveSearch range:NSMakeRange(start,text.length-start)];if(r.location==NSNotFound&&start>0)r=[text rangeOfString:needle options:NSCaseInsensitiveSearch range:NSMakeRange(0,start)];if(r.location!=NSNotFound){self.codeView.selectedRange=r;[self.codeView scrollRangeToVisible:r];[self.codeView becomeFirstResponder];}else{self.syntax.text=@"Không tìm thấy";self.syntax.textColor=NKC(0xFFB545);}}
- (void)replaceAll:(NSString*)needle with:(NSString*)replacement{if(!needle.length)return;NSString *text=self.codeView.text?:@"";NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:[NSRegularExpression escapedPatternForString:needle] options:NSRegularExpressionCaseInsensitive error:nil];NSUInteger hits=[re numberOfMatchesInString:text options:0 range:NSMakeRange(0,text.length)];if(!hits){self.syntax.text=@"Không có kết quả để thay";self.syntax.textColor=NKC(0xFFB545);return;}NSString *next=[re stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0,text.length) withTemplate:replacement?:@""];self.codeView.text=next;self.dirty=YES;[self highlight];[self updateLineNumbers];[self scheduleAutosave];self.syntax.text=[NSString stringWithFormat:@"Đã thay %lu vị trí",(unsigned long)hits];self.syntax.textColor=NKGreen();}
- (void)showSnippetMenu{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"NKTouch Snippets" message:@"Chèn API tại vị trí con trỏ" preferredStyle:UIAlertControllerStyleActionSheet];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;NSArray *rows=@[@[@"Tap",@"nk.tap(120, 450)"],@[@"Hold",@"nk.hold(120, 450, 800)"],@[@"Swipe",@"nk.swipe(120, 700, 120, 250, 450)"],@[@"Sleep",@"nk.sleep(500)"],@[@"Text",@"nk.text(\"hello\")"],@[@"Open App",@"nk.openApp(\"com.example.app\")"],@[@"Screenshot",@"nk.screenshot(\"/var/mobile/shot.jpg\")"],@[@"Find Image",@"nk.findImage(\"/var/mobile/button.png\", 2, 0.8, 0.8)"],@[@"OCR",@"nk.ocr(0, 0, 750, 300, \"en-US\")"],@[@"HTTP GET",@"local r = assert(nk.http.get(\"https://example.com\"))"]];__weak typeof(self)w=self;for(NSArray *r in rows){NSString *title=r[0],*code=r[1];[a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w insertSnippetText:code];}]];}[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)insertSnippetText:(NSString*)snippet{if(!snippet.length)return;NSRange sel=self.codeView.selectedRange;NSMutableString *text=[self.codeView.text?:@"" mutableCopy];if(NSMaxRange(sel)>text.length)sel=NSMakeRange(text.length,0);[text replaceCharactersInRange:sel withString:snippet];self.codeView.text=text;self.codeView.selectedRange=NSMakeRange(sel.location+snippet.length,0);self.dirty=YES;[self highlight];[self updateLineNumbers];[self scheduleAutosave];[self.codeView becomeFirstResponder];}
- (void)insertTapSnippet{[self insertSnippetText:@"nk.tap(120, 450)"];}
- (void)insertSleepSnippet{[self insertSnippetText:@"nk.sleep(500)"];}
- (void)insertSwipeSnippet{[self insertSnippetText:@"nk.swipe(120, 700, 120, 250, 450)"];}
- (void)insertTextSnippet{[self insertSnippetText:@"nk.text(\"hello\")"];}
- (void)insertHTTPSnippet{[self insertSnippetText:@"local r = assert(nk.http.get(\"https://example.com\"))"];}
- (NSString*)backupDirectory{NSString *root=@"/var/mobile/Library/NKTouch/backups";NSString *dir=[root stringByAppendingPathComponent:self.scriptName?:@"script.lua"];[[NSFileManager defaultManager]createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];return dir;}
- (void)backupCurrentIfNeeded{NSString *path=NKPath(self.scriptName);NSString *old=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];NSString *now=self.codeView.text?:@"";if(!old||[old isEqualToString:now])return;NSTimeInterval t=NSDate.date.timeIntervalSince1970;if(self.lastBackupAt>0&&t-self.lastBackupAt<30)return;self.lastBackupAt=t;NSDateFormatter *df=[[NSDateFormatter alloc]init];df.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];df.dateFormat=@"yyyyMMdd-HHmmss";NSString *name=[[df stringFromDate:NSDate.date]stringByAppendingPathExtension:@"lua"];NSString *out=[[self backupDirectory]stringByAppendingPathComponent:name];[old writeToFile:out atomically:YES encoding:NSUTF8StringEncoding error:nil];NSArray *files=[[[NSFileManager defaultManager]contentsOfDirectoryAtPath:[self backupDirectory] error:nil]sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];if(files.count>12){for(NSUInteger i=0;i<files.count-12;i++)[[NSFileManager defaultManager]removeItemAtPath:[[self backupDirectory]stringByAppendingPathComponent:files[i]] error:nil];}}
- (void)scheduleAutosave{[self.autosaveTimer invalidate];self.autosaveTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(autosaveNow) userInfo:nil repeats:NO];}
- (void)autosaveNow{[self.autosaveTimer invalidate];self.autosaveTimer=nil;if(!self.dirty)return;if([self save]){self.syntax.text=@"Đã tự lưu";self.syntax.textColor=NKGreen();}}
- (void)showBackupMenu{NSArray *files=[[[NSFileManager defaultManager]contentsOfDirectoryAtPath:[self backupDirectory] error:nil]sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];if(!files.count){self.syntax.text=@"Chưa có backup";self.syntax.textColor=NKC(0xFFB545);return;}UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Backup gần đây" message:@"Chọn bản muốn khôi phục" preferredStyle:UIAlertControllerStyleActionSheet];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;__weak typeof(self)w=self;NSInteger shown=0;for(NSString *f in [files reverseObjectEnumerator]){if(shown++>=8)break;[a addAction:[UIAlertAction actionWithTitle:f style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;[w restoreBackup:f];}]];}[a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)restoreBackup:(NSString*)file{NSString *p=[[self backupDirectory]stringByAppendingPathComponent:file?:@""];NSString *text=[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];if(!text)return;[self backupCurrentIfNeeded];self.codeView.text=text;self.dirty=YES;[self highlight];[self updateLineNumbers];[self autosaveNow];self.syntax.text=@"Đã khôi phục backup";self.syntax.textColor=NKGreen();}
'''

insert_marker = '- (void)viewWillDisappear:(BOOL)a{[super viewWillDisappear:a];if(self.dirty)[self save];}\n@end\n\n#pragma mark - AI prompt'
replacement = editor_pro + '\n- (void)viewWillDisappear:(BOOL)a{[self.autosaveTimer invalidate];self.autosaveTimer=nil;if(self.dirty)[self save];[super viewWillDisappear:a];}\n@end\n\n#pragma mark - AI prompt'
if insert_marker not in s:
    raise SystemExit('editor end marker missing')
s = s.replace(insert_marker, replacement, 1)

for required in (
    'V0.7.5.3 Editor Pro',
    'setupEditorPro',
    'updateLineNumbers',
    'Tìm / Thay thế',
    'NKTouch Snippets',
    'scheduleAutosave',
    '/var/mobile/Library/NKTouch/backups',
    'Đã tự lưu',
    'Editor ▾',
):
    if required not in s:
        raise SystemExit(f'missing Editor Pro marker: {required}')

settings.write_text(s)
print('Applied NKTouch v0.7.5.3 Editor Pro')
