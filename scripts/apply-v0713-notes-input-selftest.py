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
assert src.count(row) == 1, "cannot find Lua Library Samples row"
start = src.index(row)
end = src.index("\n",start)
line=src[start:end]
needle='}else if(ip.row==self.scripts.count){[self.navigationController pushViewController:[[NSClassFromString(@"NKLuaToolsViewController") alloc]init] animated:YES];}}'
assert line.count(needle) == 1, "unexpected Samples handler baseline"
extra='}else if(ip.row==self.scripts.count+1){[self.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:@"test_inputtext_notes.lua"] animated:YES];}}'
src=src[:start]+line.replace(needle,needle[:-2]+extra,1)+src[end:]
assert 'NKSaveTarget(sampleName,@"com.apple.mobilenotes",@"Ghi chú")' in src
assert 'initWithScriptName:@"test_inputtext_notes.lua"' in src
ui.write_text(src)
print("NKTouch v0.7.13: bundled Notes inputText example linked in Lua Workspace")
