"""Test effective nktouch module after v0.7.12 + v0.7.16 DEV overlays.

Offline staged smoke-test: no iOS compile, no .deb, no real touch or text.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/"lua/nktouch.lua"
CLI=ROOT/"scripts/apply-v0716-cli-parser.py"
CONTRACT=ROOT/"scripts/apply-v0716-command-contract.py"

class StagedModuleIntegration(unittest.TestCase):
    @unittest.skipUnless(shutil.which("lua"),"host Lua 5.4 required")
    def test_effective_v2_input_globals_and_argument_guards(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)/"layout/usr/share/nktouch/lua"
            directory.mkdir(parents=True)
            nktouch=directory/"nktouch.lua"
            text=BASE.read_text()
            old="M.inputText=M.text"
            self.assertEqual(text.count(old),1)
            text=text.replace(old,"M.legacyInputText=M.text",1)
            anchor="function M.inputPassword(value,options)\n"
            self.assertEqual(text.count(anchor),1)
            text=text.replace(anchor,'''function M.inputText(value,options)
  return M.inputTextV2(value,options)
end
'''+anchor,1)
            nktouch.write_text(text)
            for name in ("nkinput_v2.lua","nktouch_v7.lua","nkjson.lua",
                         "nknet.lua","nkcommand_contract.lua","nkvision.lua"):
                shutil.copy(ROOT/"lua"/name,directory/name)
            for script in (CLI,CONTRACT):
                r=subprocess.run(["python3",str(script),str(Path(tmp))],
                                 capture_output=True,text=True)
                self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            staged=nktouch.read_text()
            self.assertIn('require("nkcommand_contract").install(M)',staged)
            self.assertIn('function M.inputText(value,options)',staged)
            self.assertIn('local function wireNumbers',staged)
            harness=r'''
package.path=arg[1].."/?.lua;"..package.path
local dispatch,taps=0,0
package.preload.nkcore=function()
 return {DIRECT=true,VERSION="host",
   inputTextV2=function(text,mode)
     dispatch=dispatch+1
     assert(mode=="direct")
     assert(text=="Xin chào 😀\n;;")
     return true
   end,
   tap=function(x,y) taps=taps+1;return true end,
 }
end
local nk=require("nktouch_v7")
assert(nk.COMMAND_CONTRACT_VERSION=="0.7.16-dev")
nk.installAutoTouchCompat()
local ok,meta=inputText("Xin chào 😀\n;;")
assert(ok==true and meta.sent==true and dispatch==1)
local invalid,reason,kind=nk.tap(-1,200)
assert(invalid==nil and kind=="INVALID" and taps==0)
local tapped=nk.tap(200,300)
assert(tapped==true and taps==1)
local legacy,err,code=nk.legacyInputText("line\nline")
assert(legacy==nil and code=="INVALID")
local invalidWait,waitErr,waitCode=nk.waitText(0,0,200,100,"",5000,250,"")
assert(invalidWait==nil and waitCode=="INVALID")
print("[NKCMD][STAGED] PASS effective inputText v2 and guarded legacy APIs")
'''
            file=Path(tmp)/"harness.lua";file.write_text(harness)
            result=subprocess.run(["lua",str(file),str(directory)],
                  capture_output=True,text=True,timeout=10,cwd=ROOT)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn("[NKCMD][STAGED] PASS",result.stdout)

if __name__=="__main__":
    unittest.main()
