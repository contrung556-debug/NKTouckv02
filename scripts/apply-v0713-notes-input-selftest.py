#!/usr/bin/env python3
"""Add a built-in Apple Notes inputText example to staged NKTouch Lua Workspace."""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v0713-notes-input-selftest.py <staged-upstream>")
root = Path(sys.argv[1])
ui = root / "zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if not ui.is_file():
    raise SystemExit("missing staged Lua Workspace")
src = ui.read_text()

# Target Apps functions were defined after the Library section in v0.7.11;
# provide explicit declarations before the newly added Library call sites.
library_anchor = "#pragma mark - Library\n"
assert src.count(library_anchor) == 1, "missing Lua Library section"
src = src.replace(library_anchor, """static NSDictionary *NKTargetForScript(NSString *script);
static BOOL NKSaveTarget(NSString *script, NSString *bundle, NSString *name);

""" + library_anchor, 1)

anchor = '    if(NKScripts().count==0)[NKStarter() writeToFile:NKPath(@"main.lua") atomically:YES encoding:NSUTF8StringEncoding error:nil];'
assert src.count(anchor) == 1, "cannot find Lua Library installation hook"
sample = r'''
    // Install the packaged example exactly once per missing script. Never
    // overwrite user edits, and set Notes as target ONLY on first installation.
    NSString *sampleName=@"test_inputtext_notes.lua";
    NSString *samplePath=NKPath(sampleName);
    NSFileManager *sampleFS=[NSFileManager defaultManager];
    if (![sampleFS fileExistsAtPath:samplePath]) {
        NSString *packaged=@"/var/jb/usr/share/nktouch/examples/test_inputtext_notes.lua";
        NSError *sampleError=nil;
        if ([sampleFS copyItemAtPath:packaged toPath:samplePath error:&sampleError]) {
            if (!NKTargetForScript(sampleName))
                NKSaveTarget(sampleName,@"com.apple.mobilenotes",@"Ghi chú");
        } else NSLog(@"NKTouch built-in Notes selftest unavailable: %@",sampleError);
    }
'''
src = src.replace(anchor,anchor+"\n"+sample,1)

# Existing Samples row is decorative in v0.7.12; wire it to the actual
# bundled script so the example is discoverable without typing a filename.
row = '- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{'
library_start=src.index("#pragma mark - Library\n")
library_end=src.index("#pragma mark - Editor\n",library_start)
section=src[library_start:library_end]
assert section.count(row) == 1, "cannot find Lua Library Samples row"
# Handle the Samples row first. The retained Editor Pro patches modify the
# remainder of didSelectRowAtIndexPath; don't match or rewrite their branches.
sample_handler='if(ip.row==self.scripts.count+1){[self.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:@"test_inputtext_notes.lua"] animated:YES];return;}'
section=section.replace(row,row+sample_handler,1)
src=src[:library_start]+section+src[library_end:]
assert 'NKSaveTarget(sampleName,@"com.apple.mobilenotes",@"Ghi chú")' in src
assert 'initWithScriptName:@"test_inputtext_notes.lua"' in src
ui.write_text(src)
print("NKTouch v0.7.13: bundled Notes inputText example linked in Lua Workspace")
