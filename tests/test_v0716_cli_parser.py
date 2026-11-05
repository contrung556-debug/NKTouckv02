"""NKTouch dev: malformed CLI replies never crash Lua or fabricate colors."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
PATCH=ROOT/"scripts/apply-v0716-cli-parser.py"
LUA=ROOT/"lua/nktouch.lua"

class LegacyCLIParserTests(unittest.TestCase):
    def test_patch_inserts_strict_decoder(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"layout/usr/share/nktouch/lua/nktouch.lua"
            p.parent.mkdir(parents=True)
            p.write_text(LUA.read_text())
            result=subprocess.run(["python3",str(PATCH),tmp],
                                    capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            txt=p.read_text()
            self.assertIn('wireNumbers(s,4)',txt)
            self.assertIn('wireNumbers(s,withPos and 5 or 3)',txt)
            self.assertIn('"PARSE"',txt)
            self.assertIn('"NOT_FOUND"',txt)
            self.assertIn('return os.time()*1000',txt)
            self.assertIn('core.sleep(math.min(interval,remain))',txt)

    @unittest.skipUnless(shutil.which("lua"),"host Lua 5.4 needed")
    def test_actual_staged_decoder_with_cli_mocks(self):
        harness=r'''
-- No real NKTouch or iPhone IPC. Stub the fallback CLI.
package.preload.nkcore=function()error("no iOS core in host test")end
local answers={}
io.popen=function(cmd)
 assert(type(cmd)=="string" and cmd:find("nktouchctl",1,true))
 local reply=table.remove(answers,1)
 assert(reply~=nil,"unexpected extra CLI call")
 return {read=function()return reply end,close=function()return true,"exit",0 end}
end
local nk=assert(loadfile(arg[1]))()
local function expect(name,data,kind)
 answers[#answers+1]=data
 local value,err,code
 if name=="pixel" then value,err,code=nk.getColor(20,30)
 elseif name=="find-color" then
   value,err,code=nk.findColor(0,0,300,400,0,255,0,255,0,255,0)
 else value,err,code=nk.findImage("/var/mobile/t.png",2,0.8,0.8) end
 if kind then
  assert(value==nil and code==kind,name..": expected "..kind.." got "..tostring(code))
  assert(type(err)=="string" and #err>0,"no parse error message")
 else
  assert(type(value)=="table",name..": valid reply rejected "..tostring(err))
 end
 return value
end
local c=expect("pixel","12;;33;;45")
assert(c.packed==12*65536+33*256+45)
local hit=expect("find-color","100;;200;;1;;2;;3")
assert(hit.x==100 and hit.y==200 and hit.packed==65536+512+3)
local box=expect("image","5.5;;6;;20;;30")
assert(box.x==5.5 and box.width==20)
expect("pixel","..;;33;;45","PARSE")
expect("pixel","256;;33;;45","PARSE")
expect("pixel","1;;2;;nan","PARSE")
expect("pixel","1;;2","PARSE")
expect("find-color","-1;;-1;;-1;;-1;;-1","NOT_FOUND")
expect("find-color","-1;;-1;;1;;2;;3","NOT_FOUND")
expect("find-color","12;;13;;256;;2;;3","PARSE")
expect("find-color","12;;13;;2;;3;;4;;5","PARSE")
expect("image","-1;;-1;;0;;0","NOT_FOUND")
expect("image","3;;4;;-1;;30","PARSE")
expect("image","3;;;;20;;30","PARSE")
expect("image","3;;4;;20;;30\n1","PARSE")
assert(#answers==0)
print("[NKCMD][CLI_PARSER] PASS malformed replies rejected without exception")
'''
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"layout/usr/share/nktouch/lua/nktouch.lua"
            p.parent.mkdir(parents=True);p.write_text(LUA.read_text())
            patch=subprocess.run(["python3",str(PATCH),tmp],
                                capture_output=True,text=True)
            self.assertEqual(patch.returncode,0,patch.stderr)
            sample=Path(tmp)/"test.lua";sample.write_text(harness)
            run=subprocess.run(["lua",str(sample),str(p)],capture_output=True,
                               text=True,timeout=12,cwd=ROOT)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            self.assertIn("[NKCMD][CLI_PARSER] PASS",run.stdout)

if __name__=="__main__":
    unittest.main()
