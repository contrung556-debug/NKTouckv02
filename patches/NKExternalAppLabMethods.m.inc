// NKTouch v0.8.3 External App Test: no HID, typing or user-text logging.
// Reuses the existing trusted Lua task supervisor and Target App picker.
- (void)labChooseExternalApp {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"External App Test"
        message:@"Chọn ứng dụng. NKTouch sẽ khởi động Lua, tự mở ứng dụng đó, đợi 5 giây rồi kiểm tra OCR/Color/Memory và an toàn Touch/InputText (chỉ đọc). Tránh màn hình chứa mật khẩu hoặc mã riêng tư."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ"
        style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Chọn ứng dụng"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        __strong typeof(weakSelf) owner=weakSelf;
        if (!owner) return;
        NSString *token=[[NSUUID.UUID.UUIDString
              stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
        NSString *filename=[NSString stringWithFormat:@"nktestlab_external_%@.lua",
                            [token substringToIndex:12]];
        NKTargetAppPickerViewController *picker=[NKTargetAppPickerViewController new];
        picker.script=filename;
        __weak typeof(owner) weakOwner=owner;
        picker.selected=^{
            __strong typeof(weakOwner) view=weakOwner;
            if (!view) return;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),
                dispatch_get_main_queue(),^{ [view labStartExternalRunner:filename]; });
        };
        [owner.navigationController pushViewController:picker animated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)labStartExternalRunner:(NSString *)filename {
    NSDictionary *target=NKTargetForScript(filename);
    NSString *bundle=target[@"bundle"];
    if (!NKTargetValidID(bundle)) {
        [self labAlert:@"Chưa chọn ứng dụng" message:@"Chọn ứng dụng hợp lệ để kiểm tra."];
        return;
    }
    (void)NKScripts();
    NSFileManager *fs=NSFileManager.defaultManager;
    NSError *error=nil;
    if (![fs createDirectoryAtPath:@"/var/mobile/Library/NKTouch/tmp"
      withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self labAlert:@"Không chuẩn bị được Test Lab"
               message:error.localizedDescription?:@"Lỗi thư mục báo cáo"];
        return;
    }
    NSString *path=NKPath(filename);
    if ([fs fileExistsAtPath:path]) {
        [self labAlert:@"Script đã tồn tại" message:@"Không ghi đè script đã có."];
        return;
    }
    NSString *runID=[NSString stringWithFormat:@"external_%@",
        [[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString]];
    NSString *source=[NSString stringWithFormat:
        @"-- NKTouch External App Test v0.8.3; READ ONLY\n"
         @"-- This child runs through the trusted nktask process, independent of NKTouch UI.\n"
         @"local nk=require('nktouch_v7')\n"
         @"local bundle=%@\n"
         @"local started,err,code=nk.openApp(bundle)\n"
         @"assert(started,'EXTERNAL_OPEN_FAILED: '..tostring(code or err))\n"
         @"local ready,why,kind=nk.waitApp(bundle,8000,200)\n"
         @"assert(ready,'EXTERNAL_NOT_FOREGROUND: '..tostring(kind or why))\n"
         @"print('[NKLAB][EXTERNAL] app='..bundle..' settling=5s read_only=true')\n"
         @"for i=1,5 do\n"
         @"  nk.sleep(1000)\n"
         @"  assert(nk.foreground()==bundle,'EXTERNAL_FOREGROUND_CHANGED_DURING_SETTLE')\n"
         @"end\n"
         @"local result=require('nktestlab').run({run_id=%@,\n"
         @"  selected={'ocr','color','touch','input','memory'},\n"
         @"  external={enabled=true,expected_bundle=bundle},\n"
         @"  touch={enabled=false},input={enabled=false},network={enabled=false},\n"
         @"  memory={loops=10}})\n"
         @"if result.fail>0 then error('External App Test FAILED; see Task Center Logs',0) end\n",
         NKLuaQuoted(bundle),NKLuaQuoted(runID)];
    if (![source writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self labAlert:@"Không tạo được Lua" message:error.localizedDescription?:@"Lỗi ghi script"];
        return;
    }
    self.summary.text=[NSString stringWithFormat:
        @"Đang khởi động kiểm thử trên %@. Đợi ứng dụng tự mở.\n"
         @"Trở lại NKTouch → Báo cáo / Task Center.",target[@"name"]?:bundle];
    // "target-run" starts the existing nktask supervisor without injecting a
    // second daemon. The selected application is opened INSIDE the Lua child.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        int rc=-1;
        NSString *output=NKLuaRun(@[@"target-run",path],&rc);
        if (rc!=0) dispatch_async(dispatch_get_main_queue(), ^{
            [self labAlert:@"External App Test không chạy"
                   message:output?:@"Kiểm tra Task Center và chạy lại."];
        });
    });
}
