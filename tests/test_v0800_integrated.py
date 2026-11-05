"""NKTouch v0.8.0 integrated beta regression gates.

Uses host Lua 5.4 mocks. No claim of actual iOS OCR, HID or crash proof.
"""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

HARNESS=r'''
package.path="lua/?.lua;"..package.path
local json=require("nkjson")
local snapshot=require("nksnapshot")
local actions=require("nkactions")
local diag=require("nkdiagnostics")
local sdk=require("nksdk")
assert(type(snapshot.capture)=="function")
assert(type(actions.gesture)=="function")
assert(type(diag.readTask)=="function")
assert(type(sdk.new)=="function")

local frameCount,ocrCount,swipes,taps,textSends=0,0,0,0,0
local clock=0
local bundle="com.apple.mobilenotes"
local nk={
 screen=function() return "750.000000;;1334.000000" end,
 foreground=function() return bundle end,
 tap=function(x,y) taps=taps+1;return true end,
 hold=function(x,y,ms) taps=taps+1;return true end,
 swipe=function(x,y,x2,y2,ms) swipes=swipes+1;return true end,
 inputText=function(txt) textSends=textSends+1
   return true,{sent=true,verified=false} end,
}
nk.withFrame=function(cb)
 frameCount=frameCount+1
 local f={
  info=function()return {width=750,height=1334,format="jpeg",rgba_bytes=0,gray_bytes=0}end,
  getColor=function(_,x,y)return {red=10,green=20,blue=30,packed=10*65536+20*256+30}end,
  findColor=function(_,x,y,w,h,r1,r2,g1,g2,b1,b2,skip)
   if r1>10 or r2<10 then return nil,"not found","NOT_FOUND"end
   return {x=x,y=y,red=10,green=20,blue=30,packed=10*65536+20*256+30}
  end,
  ocr=function()
   ocrCount=ocrCount+1
   return "PUBLIC DEMO TEXT"
  end,
  findImage=function()return nil,"no template","NOT_FOUND"end
 }
 return cb(f)
end

local call={
 pixels={{x=0,y=0},{x=749,y=1333}},
 colors={{x=15,y=16,w=2,h=2,
          rmin=10,rmax=10,gmin=20,gmax=20,bmin=30,bmax=30},
         {x=15,y=16,w=2,h=2,
          rmin=0,rmax=5,gmin=20,gmax=20,bmin=30,bmax=30}},
 ocr={{x=0,y=0,w=750,h=220,language=""}},
 templates={{path="/tmp/not-a-template.png"}}
}
local result,err,code=snapshot.capture(call,{nk=nk})
assert(result,err or code)
assert(result.frame_count==1 and frameCount==1)
assert(result.width==750 and result.height==1334)
assert(result.pixels[1].status=="PASS" and result.pixels[2].status=="PASS")
assert(result.colors[1].status=="PASS" and result.colors[2].status=="NOT_FOUND")
assert(result.ocr[1].status=="PASS" and result.ocr[1].bytes>0)
assert(result.ocr[1].text==nil,"private OCR text must be omitted unless opt in")
assert(result.templates[1].status=="NOT_FOUND")
assert(result.errors==0)
local bad=snapshot.capture({pixels={{x=750,y=0}}},{nk=nk})
assert(bad.pixels[1].status=="FAIL")
assert(taps==0 and textSends==0 and swipes==0)
local secret=snapshot.capture({ocr={{x=0,y=0,w=750,h=220}}},{nk=nk,include_text=true})
assert(secret.ocr[1].text=="PUBLIC DEMO TEXT")

local value=snapshot.waitText("PUBLIC",{x=0,y=0,w=750,h=220},{
  nk=nk,now=function()return clock end,
  sleep=function(ms)clock=clock+ms;return true end,
  max_attempts=3,timeout_ms=1000,interval_ms=100
})
assert(value and value.found and value.bytes>0)
local found=snapshot.waitColor({
  x=15,y=16,w=2,h=2,rmin=10,rmax=10,
  gmin=20,gmax=20,bmin=30,bmax=30
},{
  nk=nk,now=function()return clock end,
  sleep=function(ms)clock=clock+ms;return true end
})
assert(found and found.found and found.x==15)

local denied,e,c=actions.gesture(nk,{
  enabled=true,confirmed=false,bundle=bundle,action="tap",x=15,y=30
})
assert(denied==nil and c=="NOT_CONFIRMED" and taps==0)
denied,e,c=actions.gesture(nk,{
  enabled=true,confirmed=true,bundle="com.apple.mobilesafari",action="tap",x=15,y=30
})
assert(denied==nil and c=="WRONG_APP" and taps==0)
denied,e,c=actions.gesture(nk,{
  enabled=true,confirmed=true,bundle=bundle,action="tap",x=750,y=30
})
assert(denied==nil and c=="INVALID" and taps==0)
local ok,meta=actions.gesture(nk,{
  enabled=true,confirmed=true,bundle=bundle,action="tap",x=15,y=30
})
assert(ok and meta.sent and not meta.visually_confirmed and taps==1)
ok,meta=actions.gesture(nk,{
  enabled=true,confirmed=true,bundle=bundle,action="swipe",
  x1=40,y1=50,x2=80,y2=90,ms=400
})
assert(ok and swipes==1 and taps==1)
denied,e,c=actions.typeText(nk,{
  enabled=true,confirmed=true,bundle=bundle,
  x=15,y=30,text="",secure=false
})
assert(denied==nil and c=="INVALID" and textSends==0)
denied,e,c=actions.typeText(nk,{
  enabled=true,confirmed=true,bundle=bundle,
  x=15,y=30,text="sensitive",secure=true
})
assert(denied==nil and c=="SECURE" and textSends==0)
ok,meta=actions.typeText(nk,{
  enabled=true,confirmed=true,bundle=bundle,
  x=15,y=30,text="Chào NKTouch 👋"
})
assert(ok and meta.attempts==1 and not meta.verified)
assert(taps==2 and textSends==1)

local trace,er,ec=diag.create({persist=true,path=arg[1]})
assert(trace,er or ec)
local wrapped=assert(trace:wrap({
  ocr=function()return "SECRET OTP 928361"end,
  inputText=function()return nil,"very sensitive passphrase","UNVERIFIED"end,
  tap=function()error("SECRET FROM EXCEPTION",0)end
}))
assert(wrapped.ocr(0,0,100,100)=="SECRET OTP 928361")
local p,pe,pc=wrapped.inputText("private data")
assert(p==nil and pc=="UNVERIFIED")
local success,why=pcall(wrapped.tap,1,2)
assert(not success and why:find("SECRET FROM EXCEPTION",1,true))
local report=trace:snapshot()
assert(report.last_api=="tap" and report.last_status=="EXCEPTION")
assert(not report.in_flight)
local encoded=assert(json.encode(report))
for _,part in ipairs({"OTP","928361","private data","very sensitive","SECRET FROM"}) do
  assert(not encoded:find(part,1,true),"trace leaked "..part)
end
local f=assert(io.open(arg[1],"rb"))
local disk=f:read("*a");f:close()
local parsed=assert(json.decode(disk))
assert(parsed.last_api=="tap" and parsed.last_status=="EXCEPTION")
assert(not disk:find("928361",1,true))

local task=assert(diag.readTask("T1000-777",{directory=arg[2]}))
assert(task.crashed and task.signal==11 and task.exit_code==139)
assert(task.duration_seconds==4 and task.finished)
local forbidden,why,code=diag.readTask("../../../../etc/shadow",{directory=arg[2]})
assert(forbidden==nil and code=="INVALID")
local client=assert(sdk.new({nk=nk,trace=true,persist=false}))
local out=assert(client:inspect({pixels={{x=40,y=50}}}))
assert(out.frame_count==1)
local t=client:report()
assert(t.last_api=="withFrame")
print("[NK0800][HOST] INTEGRATED_OK frames="..frameCount.." taps="..taps)
'''

class Integrated(unittest.TestCase):
    def test_staging_and_ui_contract(self):
        for name in ("nkdiagnostics","nksnapshot","nkactions","nksdk"):
            content=(ROOT/"lua"/(name+".lua")).read_text()
            self.assertIn('0.8.0-beta',content)
        s=(ROOT/"lua/nktestlab.lua").read_text()
        self.assertIn('handlers.diagnostics=function()',s)
        self.assertIn('handlers.ocr=function()',s)
        self.assertIn('handlers.memory=function()',s)
        ui=(ROOT/"patches/NKTestLabUIViewController.m.inc").read_text()
        self.assertIn('Diagnostics & Crash',ui)
        self.assertIn('labShowReport',ui)
        self.assertIn('memory={loops=10}',ui)
        self.assertIn('addObjectsFromArray:@[@"ocr",@"color",@"touch",@"input",@"memory"]',ui)

    @unittest.skipUnless(shutil.which("lua") and shutil.which("luac"),"Lua 5.4 required")
    def test_snapshot_actions_diagnostics_and_sdk(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            trace=root/"trace.json"
            taskdir=root/"tasks";taskdir.mkdir()
            (taskdir/"T1000-777.state").write_text(
              "id=T1000-777\nstate=failed\nstarted_at=100\nended_at=104\n"
              "exit_code=139\nsignal=11\n")
            path=root/"integrated.lua";path.write_text(HARNESS)
            compile_result=subprocess.run(["luac","-p",str(path)],
                cwd=ROOT,capture_output=True,text=True)
            self.assertEqual(compile_result.returncode,0,compile_result.stderr)
            p=subprocess.run(["lua",str(path),str(trace),str(taskdir)],
                cwd=ROOT,capture_output=True,text=True,timeout=20)
            self.assertEqual(p.returncode,0,p.stdout+p.stderr)
            self.assertIn("[NK0800][HOST] INTEGRATED_OK",p.stdout)
            doc=json.loads(trace.read_text())
            self.assertEqual(doc["last_status"],"EXCEPTION")

if __name__=="__main__":
    unittest.main()
