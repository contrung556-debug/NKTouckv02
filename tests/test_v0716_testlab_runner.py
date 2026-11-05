"""NKTouch v0.7.16 Lab core: no-device host Lua acceptance tests."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
LAB=ROOT/"lua/nktestlab.lua"
UI=ROOT/"patches/NKTestLabUIViewController.m.inc"
APPLY=ROOT/"scripts/apply-v0716-testlab-ui.py"
STAGE=ROOT/"scripts/stage-v0716-testlab-dev.sh"

class NKTestLabRunner(unittest.TestCase):
    def test_static_seven_groups_and_defaults(self):
        s=LAB.read_text()
        for key in ('runtime','touch','input','color','vision','network','task'):
            self.assertIn(f'handlers.{key}=function()',s)
        self.assertIn('enabled~=true',s)
        self.assertIn('no external network by default',s)
        self.assertIn('nk.inputText(text',s)
        self.assertIn('no retry',s)
        self.assertIn('reportPath.."."..id..".tmp"',s)
        self.assertIn('os.rename(temp,reportPath)',s)
        self.assertIn('[NKLAB][SUMMARY]',s)
        self.assertIn('testlab-last.json',s)

    def test_mobile_ui_route_and_safety(self):
        s=UI.read_text()
        for key in ('NKLuaTestLabViewController','Lua Runtime','Touch Engine',
                    'Input Engine','Color Engine','Vision Core','Network & JSON',
                    'Task Stability','labCreateRunner','labShowReport','labCopyReport',
                    'testlab-last.json','nktestlab_%@.lua','NKSaveTarget(filename',
                    'initWithScriptName:filename','enabled=false',
                    'selected={%@}','run_id=\\\"%@\\\"'):
            self.assertIn(key,s)
        self.assertNotIn('nktask run',s)
        self.assertIn('if ([fs fileExistsAtPath:path])',s)

    def test_staging_no_build(self):
        src=APPLY.read_text()
        script=STAGE.read_text()
        self.assertIn('NKTestLabUIViewController.m.inc',src)
        self.assertIn('NKLuaTestLabViewController',src)
        self.assertIn('stage-v0716-command-contract-dev.sh',script)
        self.assertIn('install -m 0644 \"$ROOT/lua/nktestlab.lua\"',script)
        self.assertNotIn('dpkg-deb',script)
        self.assertNotIn('sileo-repo',script)
        compile(src,str(APPLY),"exec")

    @unittest.skipUnless(shutil.which("lua"),"Lua 5.4 is required")
    def test_host_mock_all_groups_safe_by_default(self):
        harness=r'''
package.path="lua/?.lua;"..package.path
local lab=require("nktestlab")
local tapCount,textCount,httpCount,frameCount=0,0,0,0
local mock={DIRECT=true}
mock.screen=function()return "750.000000;;1334.000000"end
mock.inputText=function(text)
 if text=="" then return nil,"invalid empty input","INVALID"end
 textCount=textCount+1
 return true,{sent=true,verified=false}
end
mock.inputPassword=function(text,opts)
 assert(opts.verify,"only secure validation is allowed in read-only test")
 return nil,"no OCR for secrets","SECURE"
end
mock.tap=function(x,y)
 if x<0 then return nil,"invalid coords","INVALID"end
 tapCount=tapCount+1;return true
end
mock.hold=function(x,y,ms)
 if x<0 then return nil,"invalid coords","INVALID"end
 tapCount=tapCount+1;return true
end
mock.swipe=function(x,y,x2,y2,ms)
 if x2<0 then return nil,"invalid coords","INVALID"end
 tapCount=tapCount+1;return true
end
mock.path=function(path)
 if path[1].t==path[2].t then return nil,"non-monotonic","INVALID"end
 tapCount=tapCount+1;return true
end
mock.getColor=function()return {red=12,green=30,blue=42,packed=12*65536+30*256+42}end
mock.matchColor=function()return true,{red=12,green=30,blue=42}end
mock.findColor=function(x,y)return {x=x,y=y}end
mock.findImage=function()error("template is disabled")end
mock.withFrame=function(cb)
 frameCount=frameCount+1
 local frame={
  info=function()return {width=750,height=1334,bytes=12000}end,
  getColor=function()return {red=12,green=30,blue=42,packed=12*65536+30*256+42}end,
  findColor=function(_,x,y)return {x=x,y=y}end,
  ocr=function()return "hello"end
 }
 return cb(frame)
end
mock.http={
 request=function(opts)
  assert(opts.url=="file:///etc/passwd")
  return nil,"invalid URL","INVALID"
 end,
 get=function()
  httpCount=httpCount+1
  return {status=200}
 end
}
mock.ping=function()return true end
mock.foreground=function()return "com.apple.mobilesafari"end
mock.sleep=function()return true end
mock.stress=function(n)assert(n==5);return {failures=0} end
local report=lab.run({run_id="host_mock_0001"},{nk=mock,
  reportPath=arg[1],now=function()return 100 end})
assert(report.pass>=15,report.pass)
assert(report.fail==0 and report.warn==0)
assert(report.skip>=4)
assert(report.status=="PASS")
assert(#report.tests>=20,#report.tests)
assert(tapCount==0 and textCount==0 and httpCount==0,
       "unsafe side effects happened without opt-in")
assert(frameCount>=1)
assert(report.groups.touch.status=="PASS")
assert(report.groups.input.status=="PASS")
print("[TESTLAB][HOST] default-safe PASS tests="..#report.tests)
'''
        with tempfile.TemporaryDirectory() as tmp:
            script=Path(tmp)/"check.lua"
            script.write_text(harness)
            report=Path(tmp)/"last.json"
            result=subprocess.run(["lua",str(script),str(report)],
                 cwd=ROOT,capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn("[TESTLAB][HOST] default-safe PASS",result.stdout)
            import json
            data=json.loads(report.read_text())
            self.assertEqual(data["status"],"PASS")
            self.assertEqual(data["run_id"],"host_mock_0001")
            self.assertEqual(len(data["selected"]),7)
            self.assertTrue(data["tests"])

    @unittest.skipUnless(shutil.which("lua"),"Lua 5.4 is required")
    def test_selected_fail_is_isolated_and_reported(self):
        harness=r'''
package.path="lua/?.lua;"..package.path
local lab=require("nktestlab")
local mock={
  screen=function() return "750.000000;;1334.000000"end,
  getColor=function()return nil,"malformed","PARSE"end,
  ping=function()return true end,
  foreground=function()return "com.apple.mobilesafari"end,
  sleep=function()return true end,
  DIRECT=false
}
local result=lab.run({selected={"color","task"},run_id="fail_isolated_01"},
                 {nk=mock,reportPath=false,now=function()return 200 end})
assert(result.fail==1 and result.groups.color.status=="FAIL")
assert(result.groups.task.status=="PASS" or result.groups.task.status=="SKIP")
assert(result.status=="FAIL")
print("[TESTLAB][HOST] isolated FAIL OK")
'''
        with tempfile.TemporaryDirectory() as tmp:
            script=Path(tmp)/"check.lua";script.write_text(harness)
            result=subprocess.run(["lua",str(script)],cwd=ROOT,
                            capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn("isolated FAIL OK",result.stdout)

    @unittest.skipUnless(shutil.which("lua"),"Lua 5.4 is required")
    def test_optin_requires_matching_foreground_before_touch(self):
        harness=r'''
package.path="lua/?.lua;"..package.path
local lab=require("nktestlab")
local taps=0
local nk={DIRECT=true}
nk.screen=function()return "750.000000;;1334.000000"end
nk.foreground=function()return "com.apple.mobilesafari"end
nk.tap=function(x,y)
 if x<0 then return nil,"bad","INVALID"end
 taps=taps+1;return true
end
nk.hold=function(x)
 if x<0 then return nil,"bad","INVALID"end
 taps=taps+1;return true
end
nk.swipe=function(x,y,x2)
 if x2<0 then return nil,"bad","INVALID"end
 taps=taps+1;return true
end
nk.path=function()return nil,"bad","INVALID"end
nk.sleep=function()return true end
local touch={enabled=true,bundle="com.apple.mobilenotes",
 tap={x=120,y=300},hold={x=120,y=300,ms=300},
 swipe={x1=120,y1=400,x2=180,y2=450,ms=500}}
local denied=lab.run({selected={"touch"},touch=touch,run_id="wrong_app_01"},
                    {nk=nk,reportPath=false})
assert(denied.fail==1 and taps==0)
touch.bundle="com.apple.mobilesafari"
local accepted=lab.run({selected={"touch"},touch=touch,run_id="touch_once_01"},
                    {nk=nk,reportPath=false})
assert(accepted.warn==1 and accepted.fail==0 and taps==3,
    "touch must dispatch exactly once each, not retry")
print("[TESTLAB][HOST] opt-in guarded PASS")
'''
        with tempfile.TemporaryDirectory() as tmp:
            script=Path(tmp)/"check.lua";script.write_text(harness)
            result=subprocess.run(["lua",str(script)],cwd=ROOT,
                           capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn("opt-in guarded PASS",result.stdout)


    @unittest.skipUnless(shutil.which("lua"),"Lua 5.4 required")
    def test_optin_input_is_foreground_gated_and_never_retried(self):
        harness=r'''
package.path="lua/?.lua;"..package.path
local lab=require("nktestlab")
local taps,insertions=0,0
local current="com.apple.mobilesafari"
local nk={DIRECT=true}
nk.screen=function()return "750.000000;;1334.000000"end
nk.foreground=function()return current end
nk.tap=function(x,y) taps=taps+1; return true end
nk.sleep=function()return true end
nk.inputText=function(text,opts)
 if text=="" then return nil,"invalid text","INVALID" end
 assert(text=="NKTouch public sample")
 insertions=insertions+1
 return true,{sent=true,verified=false,status="dispatched"}
end
nk.inputPassword=function(text,opts)
 assert(opts.verify)
 return nil,"secure OCR forbidden","SECURE"
end
local input={enabled=true,bundle="com.apple.mobilenotes",x=100,y=250,
             text="NKTouch public sample"}
local denied=lab.run({selected={"input"},input=input,run_id="input_denied_01"},
                     {nk=nk,reportPath=false})
assert(denied.fail==1 and taps==0 and insertions==0)
current="com.apple.mobilenotes"
local accepted=lab.run({selected={"input"},input=input,run_id="input_once_01"},
                      {nk=nk,reportPath=false})
assert(accepted.fail==0 and accepted.warn==1)
assert(taps==1 and insertions==1,"input must send one tap and text once")
print("[TESTLAB][HOST] input opt-in non-retrying PASS")
'''
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"test.lua";path.write_text(harness)
            r=subprocess.run(["lua",str(path)],cwd=ROOT,
                  capture_output=True,text=True,timeout=12)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("input opt-in non-retrying PASS",r.stdout)


if __name__=="__main__":
    unittest.main()
