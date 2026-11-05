#!/usr/bin/env python3
"""Stage the experimental NKTouch Test Lab without creating a package.

Input must already contain the v0.7.15 Samples picker, v0.7.16 command
guards, and existing NKTouch Lua Workspace. Patch only that staged source.
"""
from pathlib import Path
import sys

if len(sys.argv)!=2:
    raise SystemExit("usage: apply-v0716-testlab-ui.py <staged-upstream>")
root=Path(sys.argv[1])
repo=Path(__file__).resolve().parents[1]
settings=root/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if not settings.is_file():
    raise SystemExit("staged Lua Workspace source is missing")
s=settings.read_text()
block=(repo/"patches/NKTestLabUIViewController.m.inc").read_text()
assert "NKLuaTestLabViewController" not in s,"Test Lab already patched"
assert 'static BOOL NKSaveTarget(NSString *script, NSString *bundle, NSString *name);' in s, \
       "v0.7.11 Target Apps forward declaration is missing"
assert 'if(ip.row==self.scripts.count+1){[self nkShowSamples];return;}' in s, \
       "v0.7.15 Samples menu missing"
assert s.count("#pragma mark - Editor\n")==1,"ambiguous Editor insertion point"

# Avoid a new runner: open the generated script in the proven Editor, which
# performs the normal check -> nktask -> logs -> stop flow.
s=s.replace("#pragma mark - Editor\n",block+"\n#pragma mark - Editor\n",1)

# Add a discoverable dashboard entry; no changes to existing tools.
# Locate only the dashboard section. Earlier versions add additional cards
# and reorganize stack calls, so never rely on the full old 5-card sequence.
start=s.index("#pragma mark - Dashboard\n")
end=s.index("#pragma mark - Library\n",start)
dashboard=s[start:end]
anchor="[stack addArrangedSubview:status];"
if dashboard.count(anchor)!=1:
    anchor="[stack addArrangedSubview:r2];"
assert dashboard.count(anchor)==1, (
    "dashboard insertion anchor missing; last section: "+dashboard[-1400:])
newcard='''NKMenuCard *testlab=[[NKMenuCard alloc]initWithIcon:@"checkmark.shield.fill"
       title:@"NKTouch Test Lab" subtitle:@"7 nhóm lệnh • kiểm tra an toàn" tint:NKBlue()];
     [testlab addTarget:self action:@selector(nkOpenTestLab)
          forControlEvents:UIControlEventTouchUpInside];
     [testlab.heightAnchor constraintEqualToConstant:88].active=YES;
     [stack addArrangedSubview:testlab];
     '''
dashboard=dashboard.replace(anchor,newcard+anchor,1)
s=s[:start]+dashboard+s[end:]
nav='- (void)openWorkspace { [self.navigationController pushViewController:[[NSClassFromString(@"NKLuaLibraryViewController") alloc] init] animated:YES]; }'
assert s.count(nav)==1,"dashboard navigation marker changed"
s=s.replace(nav,'''- (void)nkOpenTestLab {
    [self.navigationController pushViewController:
      [[NSClassFromString(@"NKLuaTestLabViewController") alloc]init] animated:YES];
}
'''+nav,1)

# Attach the Lab to the existing four-item Samples picker.
cancel='    [menu addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];'
assert s.count(cancel)==1,"v0.7.15 Samples cancel action changed"
entry='''    [menu addAction:[UIAlertAction actionWithTitle:@"Test Lab • 7 nhóm"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        __strong typeof(weakSelf) owner=weakSelf;
        if (owner) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [owner.navigationController pushViewController:
                  [[NSClassFromString(@"NKLuaTestLabViewController") alloc]init]
                  animated:YES];
            });
        }
    }]];
'''
s=s.replace(cancel,entry+cancel,1)

for expected in ("Test Lab • 7 nhóm","nkOpenTestLab","labCreateRunner",
                 "labShowReport","testlab-last.json","NKLuaTestLabViewController",
                 "nktestlab_%@.lua","NKSaveTarget(filename"):
    assert expected in s, f"required Lab UI contract missing: {expected}"
settings.write_text(s)
print("NKTouch 0.7.16 Test Lab UI added to dashboard and Samples; no iOS build")
