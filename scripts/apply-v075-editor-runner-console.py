#!/usr/bin/env python3
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v075-editor-runner-console.py <SettingsPageViewController.m>")

p = Path(sys.argv[1])
s = p.read_text()
marker = "// NKTouch V7.5 Editor + Runner + Console"
if marker in s:
    print("NKTouch V7.5 Editor + Runner + Console already applied")
    raise SystemExit(0)

required = [
    "@implementation NKLuaEditorViewController",
    "startTaskPolling",
    "NKLuaRun",
    "NKParseKV",
    "Cú pháp hợp lệ",
]
for needle in required:
    if needle not in s:
        raise SystemExit(f"V7.5 prerequisite missing: {needle}")

# Refresh visible V7.4.1 labels without touching the retained runtime API version.
s = s.replace("NKTouch v7.4.1 ·", "NKTouch v7.5 ·")
s = s.replace("NKTouch v7.4.1 •", "NKTouch v7.5 •")
s = s.replace("-- NKTouch v7.4.1\\n", "-- NKTouch v7.5\\n")

addon = r'''

// NKTouch V7.5 Editor + Runner + Console
// Native editor polish layered on top of the retained V7.4 task/runtime core.
#import <objc/runtime.h>

@interface NK75LineNumberView : UIView
@property(nonatomic,weak) UITextView *textView;
@end

@implementation NK75LineNumberView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    UITextView *tv=self.textView;
    if(!tv || !tv.text.length)return;
    NSLayoutManager *lm=tv.layoutManager;
    NSTextContainer *tc=tv.textContainer;
    CGRect visible=CGRectMake(tv.contentOffset.x, tv.contentOffset.y, tv.bounds.size.width, tv.bounds.size.height);
    NSRange glyphs=[lm glyphRangeForBoundingRect:visible inTextContainer:tc];
    NSString *text=tv.text?:@"";
    NSDictionary *attrs=@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:10.5 weight:UIFontWeightMedium],NSForegroundColorAttributeName:NKC(0x66708D)};
    [lm enumerateLineFragmentsForGlyphRange:glyphs usingBlock:^(CGRect usedRect,CGRect fragmentRect,NSTextContainer *container,NSRange glyphRange,BOOL *stop){
        (void)usedRect;(void)container;(void)stop;
        if(glyphRange.location>=lm.numberOfGlyphs)return;
        NSUInteger ci=[lm characterIndexForGlyphAtIndex:glyphRange.location];
        if(ci>0 && ci<=text.length && [text characterAtIndex:ci-1]!='\n')return; // wrapped visual line
        NSInteger line=1;
        for(NSUInteger i=0;i<ci && i<text.length;i++)if([text characterAtIndex:i]=='\n')line++;
        CGFloat y=fragmentRect.origin.y+tv.textContainerInset.top-tv.contentOffset.y;
        NSString *n=[NSString stringWithFormat:@"%ld",(long)line];
        CGSize z=[n sizeWithAttributes:attrs];
        [n drawAtPoint:CGPointMake(MAX(2,31-z.width),y) withAttributes:attrs];
    }];
}
@end

static char NK75TimerKey;
static char NK75LineViewKey;
static char NK75ElapsedKey;
static char NK75RefreshBusyKey;
static char NK75LastLogKey;
static char NK75LogBaselineKey;

@interface NKLuaEditorViewController (NK75)
- (void)nk75_viewDidLoad;
- (void)nk75_viewWillDisappear:(BOOL)animated;
- (void)nk75_textViewDidChange:(UITextView*)textView;
@end

@implementation NKLuaEditorViewController (NK75)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class c=[NKLuaEditorViewController class];
        Method a=class_getInstanceMethod(c,@selector(viewDidLoad));
        Method b=class_getInstanceMethod(c,@selector(nk75_viewDidLoad));
        if(a&&b)method_exchangeImplementations(a,b);
        a=class_getInstanceMethod(c,@selector(viewWillDisappear:));
        b=class_getInstanceMethod(c,@selector(nk75_viewWillDisappear:));
        if(a&&b)method_exchangeImplementations(a,b);
        a=class_getInstanceMethod(c,@selector(textViewDidChange:));
        b=class_getInstanceMethod(c,@selector(nk75_textViewDidChange:));
        if(a&&b)method_exchangeImplementations(a,b);
    });
}

- (void)nk75_viewDidLoad {
    [self nk75_viewDidLoad];
    self.codeView.textContainerInset=UIEdgeInsetsMake(12,48,12,12);

    NK75LineNumberView *g=[[NK75LineNumberView alloc]init];
    g.translatesAutoresizingMaskIntoConstraints=NO;
    g.userInteractionEnabled=NO;
    g.backgroundColor=NKC(0x090E1C);
    g.textView=self.codeView;
    g.layer.borderColor=NKC(0x242D49).CGColor;
    g.layer.borderWidth=.5;
    [self.codeView.superview addSubview:g];
    [NSLayoutConstraint activateConstraints:@[
        [g.leadingAnchor constraintEqualToAnchor:self.codeView.leadingAnchor],
        [g.topAnchor constraintEqualToAnchor:self.codeView.topAnchor],
        [g.bottomAnchor constraintEqualToAnchor:self.codeView.bottomAnchor],
        [g.widthAnchor constraintEqualToConstant:38]
    ]];
    objc_setAssociatedObject(self,&NK75LineViewKey,g,OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *elapsed=[[UILabel alloc]init];
    elapsed.translatesAutoresizingMaskIntoConstraints=NO;
    elapsed.text=@"00:00";
    elapsed.textColor=NKMuted();
    elapsed.font=[UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    UIView *state=self.runState.superview;
    [state addSubview:elapsed];
    [NSLayoutConstraint activateConstraints:@[
        [elapsed.trailingAnchor constraintEqualToAnchor:state.trailingAnchor constant:-12],
        [elapsed.centerYAnchor constraintEqualToAnchor:self.runState.centerYAnchor]
    ]];
    objc_setAssociatedObject(self,&NK75ElapsedKey,elapsed,OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *more=[UIButton buttonWithType:UIButtonTypeSystem];
    more.frame=CGRectMake(0,0,36,36);
    [more setImage:NKIcon(@"ellipsis.circle",19) forState:UIControlStateNormal];
    more.tintColor=NKC(0xC7B8FF);
    if(@available(iOS 14.0,*)){
        __weak typeof(self)w=self;
        more.menu=[UIMenu menuWithTitle:@"Lua Studio" children:@[
            [UIAction actionWithTitle:@"Tìm trong code" image:NKIcon(@"magnifyingglass",14) identifier:nil handler:^(__kindof UIAction*a){(void)a;[w nk75_find];}],
            [UIAction actionWithTitle:@"Thay thế" image:NKIcon(@"arrow.triangle.2.circlepath",14) identifier:nil handler:^(__kindof UIAction*a){(void)a;[w nk75_replace];}],
            [UIAction actionWithTitle:@"Undo" image:NKIcon(@"arrow.uturn.backward",14) identifier:nil handler:^(__kindof UIAction*a){(void)a;if(w.codeView.undoManager.canUndo)[w.codeView.undoManager undo];}],
            [UIAction actionWithTitle:@"Redo" image:NKIcon(@"arrow.uturn.forward",14) identifier:nil handler:^(__kindof UIAction*a){(void)a;if(w.codeView.undoManager.canRedo)[w.codeView.undoManager redo];}],
            [UIAction actionWithTitle:@"Restart tác vụ" image:NKIcon(@"arrow.clockwise",14) identifier:nil handler:^(__kindof UIAction*a){(void)a;[w nk75_restart];}],
            [UIAction actionWithTitle:@"Copy logs" image:NKIcon(@"doc.on.doc",14) identifier:nil handler:^(__kindof UIAction*a){(void)a;[w nk75_copyLogs];}],
            [UIAction actionWithTitle:@"Clear console" image:NKIcon(@"trash",14) identifier:nil handler:^(__kindof UIAction*a){(void)a;[w nk75_clearLogs];}]
        ]];
        more.showsMenuAsPrimaryAction=YES;
    }
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithCustomView:more];

    NSTimer *timer=[NSTimer timerWithTimeInterval:.8 target:self selector:@selector(nk75_refreshRuntime) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(self,&NK75TimerKey,timer,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [g setNeedsDisplay];
}

- (void)nk75_viewWillDisappear:(BOOL)animated {
    NSTimer *timer=objc_getAssociatedObject(self,&NK75TimerKey);
    [timer invalidate];
    objc_setAssociatedObject(self,&NK75TimerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self nk75_viewWillDisappear:animated];
}

- (void)nk75_textViewDidChange:(UITextView*)textView {
    [self nk75_textViewDidChange:textView];
    NK75LineNumberView *g=objc_getAssociatedObject(self,&NK75LineViewKey);
    [g setNeedsDisplay];
}

- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
    if(scrollView==self.codeView){
        NK75LineNumberView *g=objc_getAssociatedObject(self,&NK75LineViewKey);
        [g setNeedsDisplay];
    }
}

- (BOOL)textView:(UITextView*)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString*)replacement {
    if(textView!=self.codeView || ![replacement isEqualToString:@"\n"])return YES;
    NSString *text=textView.text?:@"";
    NSUInteger p=MIN(range.location,text.length);
    NSRange lineRange=[text lineRangeForRange:NSMakeRange(p,0)];
    NSString *line=[text substringWithRange:NSMakeRange(lineRange.location,p-lineRange.location)];
    NSMutableString *indent=[NSMutableString string];
    for(NSUInteger i=0;i<line.length;i++){
        unichar c=[line characterAtIndex:i];
        if(c==' '||c=='\t')[indent appendFormat:@"%C",c]; else break;
    }
    NSString *trim=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if([trim hasSuffix:@"then"]||[trim hasSuffix:@"do"]||[trim hasSuffix:@"{"]||[trim hasPrefix:@"function "]||[trim hasPrefix:@"local function "])[indent appendString:@"  "];
    NSString *insert=[@"\n" stringByAppendingString:indent];
    textView.text=[text stringByReplacingCharactersInRange:range withString:insert];
    textView.selectedRange=NSMakeRange(range.location+insert.length,0);
    [self textViewDidChange:textView];
    return NO;
}

- (void)nk75_refreshRuntime {
    NSString *tid=self.taskID;
    if(!tid.length){
        UILabel *elapsed=objc_getAssociatedObject(self,&NK75ElapsedKey);
        elapsed.text=@"00:00";
        return;
    }
    if([objc_getAssociatedObject(self,&NK75RefreshBusyKey) boolValue])return;
    objc_setAssociatedObject(self,&NK75RefreshBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL wantsLogs=(self.mode.selectedSegmentIndex==1);
    __weak typeof(self)w=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        int sc=0;NSString *statusOut=NKLuaRun(@[@"status",tid],&sc);NSDictionary *d=NKParseKV(statusOut);
        NSString *state=d[@"state"]?:@"idle";BOOL active=NKTaskStateIsActive(state);
        int lc=-1;NSString *logOut=nil;
        if(wantsLogs||!active)logOut=NKLuaRun(@[@"logs",tid,@"200"],&lc);
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self)self=w;if(!self)return;
            objc_setAssociatedObject(self,&NK75RefreshBusyKey,@NO,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            long started=[d[@"started_at"] longLongValue];long ended=[d[@"ended_at"] longLongValue];long now=(long)NSDate.date.timeIntervalSince1970;
            long sec=started>0?MAX(0,(ended>0?ended:now)-started):0;
            UILabel *elapsed=objc_getAssociatedObject(self,&NK75ElapsedKey);
            elapsed.text=[NSString stringWithFormat:@"%02ld:%02ld",sec/60,sec%60];
            if(lc==0&&logOut.length)[self nk75_applyLog:logOut terminal:!active state:state];
        });
    });
}

- (void)nk75_applyLog:(NSString*)raw terminal:(BOOL)terminal state:(NSString*)state {
    NSString *previous=objc_getAssociatedObject(self,&NK75LastLogKey);
    if([previous isEqualToString:raw])return;
    objc_setAssociatedObject(self,&NK75LastLogKey,raw,OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSString *baseline=objc_getAssociatedObject(self,&NK75LogBaselineKey);
    NSString *shown=raw;
    if(baseline.length){
        if([raw hasPrefix:baseline])shown=[raw substringFromIndex:baseline.length];
        else objc_setAssociatedObject(self,&NK75LogBaselineKey,nil,OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    if(!shown.length)shown=@"[NKTouch] Console đã xoá • đang chờ log mới…\n";
    NSMutableAttributedString *a=[[NSMutableAttributedString alloc]initWithString:shown attributes:@{NSFontAttributeName:[UIFont monospacedSystemFontOfSize:11.2 weight:UIFontWeightRegular],NSForegroundColorAttributeName:NKC(0xC9D4FF)}];
    [shown enumerateSubstringsInRange:NSMakeRange(0,shown.length) options:NSStringEnumerationByLines usingBlock:^(NSString *line,NSRange sub,NSRange enc,BOOL *stop){
        (void)enc;(void)stop;NSString *l=line.lowercaseString;UIColor *c=nil;
        if([l containsString:@"error"]||[l containsString:@"failed"]||[l containsString:@"syntax"]||[l containsString:@"timeout"])c=NKRed();
        else if([l containsString:@"warn"]||[l containsString:@"stopped"]||[l containsString:@"pause"])c=NKC(0xFFB545);
        else if([line hasPrefix:@"[NKTask]"])c=NKC(0x6CD7FF);
        if(c&&NSMaxRange(sub)<=a.length)[a addAttribute:NSForegroundColorAttributeName value:c range:sub];
    }];
    self.console.attributedText=a;
    if(self.console.text.length)[self.console scrollRangeToVisible:NSMakeRange(self.console.text.length-1,1)];
    NSString *v=state.lowercaseString;
    if(terminal&&([v isEqualToString:@"failed"]||[v isEqualToString:@"timeout"])){
        NSInteger line=[self line:raw];
        if(line!=NSNotFound&&line>0)[self setSyntaxText:[NSString stringWithFormat:@"Runtime lỗi • dòng %ld",(long)line] color:NKRed() icon:@"xmark.octagon.fill"];
    }
}

- (void)nk75_copyLogs {
    UIPasteboard.generalPasteboard.string=self.console.text?:@"";
    self.navigationItem.prompt=@"Đã copy logs";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{self.navigationItem.prompt=nil;});
}

- (void)nk75_clearLogs {
    NSString *raw=objc_getAssociatedObject(self,&NK75LastLogKey);
    if(raw.length)objc_setAssociatedObject(self,&NK75LogBaselineKey,raw,OBJC_ASSOCIATION_COPY_NONATOMIC);
    self.console.text=@"[NKTouch] Console đã xoá • đang chờ log mới…\n";
}

- (void)nk75_restart {
    NSString *tid=self.taskID;
    if(!tid.length){[self runTapped];return;}
    self.runState.text=@"↻ Đang restart…";self.runState.textColor=NKC(0xC7B8FF);
    __weak typeof(self)w=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        int c=0;(void)NKLuaRun(@[@"stop",tid],&c);
        for(int i=0;i<24;i++){
            int sc=0;NSDictionary *d=NKParseKV(NKLuaRun(@[@"status",tid],&sc));NSString *st=[d[@"state"] lowercaseString]?:@"";
            if(!NKTaskStateIsActive(st))break;
            usleep(125000);
        }
        dispatch_async(dispatch_get_main_queue(),^{typeof(self)self=w;if(!self)return;self.taskID=nil;[self runTapped];});
    });
}

- (void)nk75_find {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Tìm trong Lua" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"Từ khoá";f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    __weak typeof(self)w=self;
    [a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Tìm tiếp" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;NSString*q=a.textFields.firstObject.text?:@"";if(!q.length)return;NSString*t=w.codeView.text?:@"";NSUInteger start=MIN(NSMaxRange(w.codeView.selectedRange),t.length);NSRange r=[t rangeOfString:q options:NSCaseInsensitiveSearch range:NSMakeRange(start,t.length-start)];if(r.location==NSNotFound)r=[t rangeOfString:q options:NSCaseInsensitiveSearch];if(r.location!=NSNotFound){w.codeView.selectedRange=r;[w.codeView scrollRangeToVisible:r];}}]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)nk75_replace {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Thay thế" message:@"Thay tất cả trong script hiện tại." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"Tìm";f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addTextFieldWithConfigurationHandler:^(UITextField*f){f.placeholder=@"Thay bằng";f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    __weak typeof(self)w=self;
    [a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Thay tất cả" style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){(void)x;NSString*f=a.textFields[0].text?:@"";NSString*r=a.textFields[1].text?:@"";if(!f.length)return;NSString*old=w.codeView.text?:@"";NSString*next=[old stringByReplacingOccurrencesOfString:f withString:r];if(![next isEqualToString:old]){w.codeView.text=next;[w textViewDidChange:w.codeView];}}]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
'''

s += addon
p.write_text(s)
print("Applied NKTouch V7.5 Editor + Runner + Console")
