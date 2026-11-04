from pathlib import Path
import subprocess
import tempfile
import unittest
import shutil

ROOT=Path(__file__).resolve().parents[1]

class InputEngineV2(unittest.TestCase):
    def test_native_and_legacy_contract(self):
        native=(ROOT/"runtime/nkcore.c").read_text()
        for key in ("NK_INPUT_V2_MAX_BYTES 8192","l_input_text_v2",
                    "memchr(raw,0,len)","4*((len+2)/3)",
                    '"inputTextV2", l_input_text_v2'):
            self.assertIn(key,native)
        lua=(ROOT/"lua/nktouch.lua").read_text()
        for key in ("M.inputText=M.text","function M.inputTextV2",
                    "function M.inputPassword"):
            self.assertIn(key,lua)
        engine=(ROOT/"lua/nkinput_v2.lua").read_text()
        for key in ("utf8.len(text)","MAX_BYTES = 8192","UNVERIFIED",
                    "function M.password"):
            self.assertIn(key,engine)
        self.assertNotIn("setClipboard(",engine)

    def test_hook_patch_compiles_against_pinned_source(self):
        patch=(ROOT/"scripts/apply-input-engine-v2.py").read_text()
        for key in ("initWithBase64EncodedString:", "NKInputV2FocusedView",
                    "nk_input_v2_id", "NSMutableOrderedSet",
                    "UISceneActivationStateForegroundActive"):
            self.assertIn(key,patch)
        upstream=ROOT/"upstream"
        if not (upstream/"appdelegate/UIKeyboard.xm").exists():
            self.skipTest("upstream missing")
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            for item in ("appdelegate/UIKeyboard.xm","pccontrol/UIKeyboard.xm"):
                (p/item).parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(upstream/item,p/item)
            r=subprocess.run(["python3",str(ROOT/"scripts/apply-input-engine-v2.py"),str(p)],
                             capture_output=True,text=True,timeout=10)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("nk_input_v2_id",(p/"pccontrol/UIKeyboard.xm").read_text())
            self.assertIn("NKInputV2FocusedView",(p/"appdelegate/UIKeyboard.xm").read_text())

    def test_version_and_package(self):
        stage=(ROOT/"scripts/prepare-v0710-input-engine-v2.sh").read_text()
        build=(ROOT/".github/workflows/build-v0710-input-engine-v2.yml").read_text()
        for key in ("prepare-v079-vision-core.sh","apply-input-engine-v2.py",
                    "nkinput_v2.lua","Version: 0.7.10"):
            self.assertIn(key,stage)
        for key in ("NK_VERSION: 0.7.10","test_v0710_input_engine_v2.py",
                    "prepare-v0710-input-engine-v2.sh"):
            self.assertIn(key,build)
        self.assertIn("publish-sileo:",build)
        self.assertIn("needs: build-rootless",build)
        self.assertIn("if: needs.build-rootless.result == 'success'",build)
        self.assertIn("publish-v0710-sileo.sh",build)

    @unittest.skipUnless(shutil.which("lua"),"lua unavailable")
    def test_unicode_password_verification_and_no_retry(self):
        script = r'''
package.path=arg[1].."/?.lua;"..package.path
local m=require("nkinput_v2")
local calls,events=0,{}
local nk={}
nk._inputNativeV2=function(s,mode)
 calls=calls+1
 events[calls]={s=s,mode=mode}
 return true
end
nk.sleep=function(ms) return true end
nk.ocr=function()return "Tiếng Việt 😀"end
local t="Tiếng Việt 😀\r\nx;;y"
local ok,meta=m.input(nk,t)
assert(ok and meta.sent and not meta.verified)
assert(calls==1 and events[1].s==t)
local ok,meta=m.input(nk,"Việt",{verify={x=0,y=0,w=200,h=60,expected="Việt"}})
assert(ok and meta.verified and calls==2)
local ok,err,code,meta=m.input(nk,"x",{verify={x=0,y=0,w=200,h=60,expected="abc"}})
assert(ok==nil and code=="UNVERIFIED" and meta.sent and calls==3)
local ok,meta=m.password(nk,"Mật_khẩu_88!")
assert(ok and meta.sent and not meta.verified and calls==4)
local ok,err,code=m.password(nk,"secret",{verify={x=0,y=0,w=50,h=50}})
assert(not ok and code=="SECURE" and calls==4)
for _,v in ipairs({"",string.rep("x",8193),"a\0b","\255bad"}) do
 local ok,err,code=m.input(nk,v)
 assert(not ok and code=="INVALID")
end
local ok,err,code=m.input(nk,"yes",{verify={x=-1,y=0,w=50,h=50}})
assert(not ok and code=="INVALID" and calls==4)
nk._inputNativeV2=function()calls=calls+1;return nil,"transport","TRANSPORT"end
local ok,err,code=m.input(nk,"no retry")
assert(not ok and calls==5)
print("INPUT_V2_HOST_OK")
'''
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"case.lua"
            p.write_text(script)
            r=subprocess.run(["lua",str(p),str(ROOT/"lua")],capture_output=True,text=True,timeout=10)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("INPUT_V2_HOST_OK",r.stdout)
