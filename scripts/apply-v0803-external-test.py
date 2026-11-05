#!/usr/bin/env python3
"""Stage the optional External App Test on the already-staged v0.8.2 UI.

The UI chooses a target and launches the proven managed Lua task; the worker
opens the target app, waits 5 seconds and collects read-only measurements.
"""
from pathlib import Path
import sys

if len(sys.argv)!=2:
    raise SystemExit("usage: apply-v0803-external-test.py <staged-upstream>")
root=Path(sys.argv[1])
repo=Path(__file__).resolve().parents[1]
settings=root/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if not settings.is_file(): raise SystemExit("Missing NKTouch Settings UI")
text=settings.read_text()
if "labChooseExternalApp" in text:
    raise SystemExit("External App Test already staged")

for contract in ("@implementation NKLuaTestLabViewController",
                 "NKTargetAppPickerViewController",
                 "static NSString *NKLuaRun(",
                 'if ([cmd isEqualToString:@"target-run"]',
                 "labCreateRunner","labShowReport"):
    if contract not in text:
        raise SystemExit("UI contract missing: "+contract)

start=text.index("@implementation NKLuaTestLabViewController")
end=text.index("@end",start)
lab=text[start:end]

def strict(old,new):
    global lab
    if lab.count(old)!=1:
        raise SystemExit(f"Expected one Lab UI anchor {old[:70]!r}; got {lab.count(old)}")
    lab=lab.replace(old,new,1)

strict('self.hint.text=@"Mặc định chọn OCR, Color, Touch, InputText, Memory. Chỉ đọc; thử chạm/nhập cần bật và xác nhận trong Lua Editor. Chọn thêm nhóm nâng cao khi cần.";',
       'self.hint.text=@"Test 5 lõi trong NKTouch hoặc kiểm tra ứng dụng bên ngoài. External App Test tự mở ứng dụng đích, đợi 5 giây rồi chỉ đọc màn hình, không tự chạm hay nhập.";')

button='''    UIButton *external=[UIButton buttonWithType:UIButtonTypeSystem];
    external.translatesAutoresizingMaskIntoConstraints=NO;
    [external setTitle:@"Test ứng dụng khác • 5 lõi" forState:UIControlStateNormal];
    external.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    external.backgroundColor=NKBlue();
    external.tintColor=UIColor.whiteColor;
    external.layer.cornerRadius=12;
    [external addTarget:self action:@selector(labChooseExternalApp)
           forControlEvents:UIControlEventTouchUpInside];

'''
strict("    self.summary=[[UILabel alloc]init];",button+"    self.summary=[[UILabel alloc]init];")
strict("    [self.view addSubview:create];\n    [self.view addSubview:self.summary];",
       "    [self.view addSubview:external];\n    [self.view addSubview:create];\n    [self.view addSubview:self.summary];")
strict("        [self.table.bottomAnchor constraintEqualToAnchor:create.topAnchor constant:-8],",
       """        [self.table.bottomAnchor constraintEqualToAnchor:external.topAnchor constant:-8],
        [external.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [external.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [external.heightAnchor constraintEqualToConstant:48],
        [external.bottomAnchor constraintEqualToAnchor:create.topAnchor constant:-8],""")

explain='''    NSDictionary *external=[report[@"external"] isKindOfClass:[NSDictionary class]]?
         report[@"external"]:nil;
    if (external) {
        [out appendFormat:@"External target=%@ | first=%@ | last=%@ | stable=%@ | result=%@\\n",
          external[@"expected_bundle"]?:@"-",
          external[@"foreground_start"]?:@"-",
          external[@"foreground_end"]?:@"-",
          [external[@"verified"] boolValue]?@"YES":@"NO",
          external[@"observation"]?:@"-"];
    }
'''
strict('    NSDictionary *timing=[report[@"timing"] isKindOfClass:[NSDictionary class]]?',
       explain+'    NSDictionary *timing=[report[@"timing"] isKindOfClass:[NSDictionary class]]?')

snippet=(repo/"patches/NKExternalAppLabMethods.m.inc").read_text()
strict("- (void)labCreateRunner {",snippet+"\n- (void)labCreateRunner {")
text=text[:start]+lab+text[end:]
for marker in ('Test ứng dụng khác • 5 lõi',"labChooseExternalApp",
               "labStartExternalRunner","NKLuaRun(@[@\"target-run\",path]",
               "external={enabled=true,expected_bundle=bundle}",
               "NKTargetAppPickerViewController","report[@\"external\"]"):
    if marker not in text:
        raise SystemExit("External App Test staging incomplete: "+marker)
settings.write_text(text)
print("NKTouch v0.8.3 External App Test integrated (artifact-only; no Sileo)")
