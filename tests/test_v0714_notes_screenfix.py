"""v0.7.14 regression checks for Notes iOS screen dimensions response."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/"examples/test_inputtext_notes_v2.lua"
PATCH=ROOT/"scripts/apply-v0714-notes-screenfix.py"

class NotesScreenFix(unittest.TestCase):
    def test_sample_safe_and_decimal_format(self):
        s=SCRIPT.read_text()
        self.assertIn('(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)',s)
        self.assertIn('math.floor(w + 0.5)',s)
        self.assertIn('nk.waitApp(NOTES_ID, 10000, 250)',s)
        self.assertIn('nk.inputText(TEST_TEXT)',s)
        self.assertLess(s.index("nk.waitApp(NOTES_ID, 10000, 250)"),
                        s.index("nk.tap(createX, createY)"))
        self.assertLess(s.index("nk.tap(bodyX, bodyY)"),
                        s.index("nk.inputText(TEST_TEXT)"))
        self.assertNotIn('if not w then w, h = tostring(value):match',s)

    def test_ui_routes_fresh_sample_without_overwriting_existing(self):
        compile(PATCH.read_text(),str(PATCH),"exec")
        with tempfile.TemporaryDirectory() as folder:
            ui=Path(folder)/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
            ui.parent.mkdir(parents=True)
            ui.write_text('''
NSString *sampleName=@"test_inputtext_notes.lua";
NSString *packaged=@"/var/jb/usr/share/nktouch/examples/test_inputtext_notes.lua";
if (!NKTargetForScript(sampleName))
  NKSaveTarget(sampleName,@"com.apple.mobilenotes",@"Ghi chú");
initWithScriptName:@"test_inputtext_notes.lua"
''')
            r=subprocess.run(["python3",str(PATCH),folder],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stderr)
            s=ui.read_text()
            self.assertEqual(s.count("test_inputtext_notes_v2.lua"),3)
            self.assertNotIn('@"test_inputtext_notes.lua"',s)
            self.assertIn('NKSaveTarget(sampleName,@"com.apple.mobilenotes",@"Ghi chú")',s)

    def test_stage_keeps_v1_sample(self):
        s=(ROOT/"scripts/prepare-v0714-notes-screenfix.sh").read_text()
        self.assertIn("prepare-v0713-notes-input-selftest.sh",s)
        self.assertIn("test_inputtext_notes_v2.lua",s)
        self.assertIn('Version: 0.7.14',s)
        self.assertIn('test_inputtext_notes.lua',s)

    @unittest.skipUnless(shutil.which("lua"), "host Lua unavailable")
    def test_lua_accepts_real_decimal_format_and_integer(self):
        harness=r'''
local expectedW,expectedH=tonumber(arg[3]),tonumber(arg[4])
local mock,events={},{}
local current="com.apple.springboard"
mock.screen=function()return arg[2] end
mock.foreground=function()return current end
mock.openApp=function(bundle)
 assert(bundle=="com.apple.mobilenotes");current=bundle
 events[#events+1]="open";return true
end
mock.waitApp=function(bundle,ms,step)
 assert(bundle==current and ms==10000 and step==250)
 events[#events+1]="wait";return true
end
mock.sleep=function(ms)events[#events+1]="sleep";return true end
mock.tap=function(x,y)
 events[#events+1]="tap"
 local index=0
 for _,name in ipairs(events) do if name=="tap" then index=index+1 end end
 if index==1 then
  assert(x==math.floor(expectedW*.91) and y==math.floor(expectedH*.91),x..","..y)
 else
  assert(x==math.floor(expectedW*.35) and y==math.floor(expectedH*.25),x..","..y)
 end
 return true
end
mock.inputText=function(text)
 assert(text=="NKTouch InputText Test 12345")
 events[#events+1]="input"
 return true,{sent=true,status="dispatched"}
end
mock.ocr=function()return "NKTouch InputText Test 12345" end
package.preload.nktouch_v7=function() return mock end
dofile(arg[1])
assert(table.concat(events,",")=="open,wait,sleep,tap,sleep,tap,sleep,input,sleep",table.concat(events,","))
print("NOTES_DECIMAL_FORMAT_OK")
'''
        with tempfile.TemporaryDirectory() as tmp:
            script=Path(tmp)/"harness.lua";script.write_text(harness)
            for value,w,h in (("750.000000;;1334.000000",750,1334),
                              ("390;;844",390,844),
                              (" 750.0 ;; 1334.0 ",750,1334)):
                result=subprocess.run(["lua",str(script),str(SCRIPT),value,str(w),str(h)],
                    capture_output=True,text=True,timeout=10)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertIn("NOTES_DECIMAL_FORMAT_OK",result.stdout)
                self.assertIn("VERIFIED_BY_OCR",result.stdout)

    @unittest.skipUnless(shutil.which("lua"), "host Lua unavailable")
    def test_invalid_dimensions_fail_before_any_tap(self):
        harness=r'''
local mock={}
mock.screen=function()return "750.invalid;;1334.000000" end
mock.tap=function()error("UNSAFE: tap before dimensions validation")end
mock.inputText=function()error("UNSAFE: input before dimensions validation")end
package.preload.nktouch_v7=function()return mock end
local ok,err=pcall(dofile,arg[1])
assert(not ok and tostring(err):find("SCREEN_FORMAT",1,true))
print("FAIL_CLOSED_OK")
'''
        with tempfile.TemporaryDirectory() as tmp:
            script=Path(tmp)/"bad.lua";script.write_text(harness)
            result=subprocess.run(["lua",str(script),str(SCRIPT)],
                                  capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn("FAIL_CLOSED_OK",result.stdout)

if __name__=="__main__":
    unittest.main()
