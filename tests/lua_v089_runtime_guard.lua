-- NKTouch v0.8.9 Runtime Reliability deterministic host-only test.
package.path="lua/?.lua;"..package.path
local guard=require("nkruntime_guard")
assert(guard.VERSION=="0.8.9-beta")
local clock=0
local sleeping=0
local cancel=false
local function now() return clock end
local function sleep(ms) assert(ms<=100); clock=clock+ms; sleeping=sleeping+1; return true end
local s=assert(guard.create({deadline_ms=800,max_steps=6,
                            max_resources=4,now=now,sleep=sleep,
                            cancelled=function() return cancel end}))
local secret="Private user input: 🌻 token=SECRET"
local ok,text=s:step("read",function() return secret end)
assert(ok and text==secret)
local snap=s:snapshot()
assert(snap.status=="RUNNING" and snap.steps==1 and snap.in_flight==false)
local function privateReport(obj)
  local function walk(value)
    if type(value)=="string" then
      assert(not value:find("SECRET",1,true))
      assert(not value:find("Private",1,true))
      assert(not value:find("token=",1,true))
    elseif type(value)=="table" then
      for key,item in pairs(value) do
        walk(key);walk(item)
      end
    end
  end
  walk(obj)
end
privateReport(snap)
local callbacks=0
local cleanupOrder={}
assert(s:defer("first",function() cleanupOrder[#cleanupOrder+1]="first";return true end))
assert(s:defer("second",function() cleanupOrder[#cleanupOrder+1]="second";return true end))
ok,text=s:step("write",function()
  callbacks=callbacks+1;return true
end,{confirmed=true,onceKey="notes.field1"})
assert(ok and callbacks==1 and text.status=="DISPATCHED_UNVERIFIED")
local f,e,c=s:step("write",function() callbacks=callbacks+1 end,
                    {confirmed=true,onceKey="notes.field1"})
assert(f==nil and c=="DUPLICATE_BLOCKED" and callbacks==1)
local dispatched=0
f,e,c=s:step("write",function()
  dispatched=dispatched+1
  error("SECRET: backend delivery ambiguous")
end,{confirmed=true,onceKey="notes.field2"})
assert(f==nil and c=="DISPATCH_UNCERTAIN" and dispatched==1)
f,e,c=s:step("write",function() dispatched=dispatched+1 end,
              {confirmed=true,onceKey="notes.field2"})
assert(f==nil and c=="DUPLICATE_BLOCKED" and dispatched==1)
f,e,c=s:step("write",function() callbacks=callbacks+1 end,
              {confirmed=false,onceKey="notes.field3"})
assert(f==nil and c=="WRITE_NOT_CONFIRMED" and callbacks==1)
ok,text=s:step("read",function() return "Hello" end)
assert(ok and text=="Hello" and callbacks==1)
ok=s:sleep(255)
assert(ok and sleeping==3 and clock==255)
local done,summary=s:finish()
assert(done and summary.closed and summary.status=="FINISHED")
assert(summary.cleanup_failures==0 and #cleanupOrder==2)
assert(cleanupOrder[1]=="second" and cleanupOrder[2]=="first")
privateReport(summary)
assert(summary.resources_pending==0)
f,e,c=s:step("read",function() error("should not run") end)
assert(f==nil and c=="CLOSED")
f,e,c=s:finish()
assert(f==nil and c=="CLOSED")

local timeout=assert(guard.create({now=now,sleep=sleep,deadline_ms=100,max_steps=3}))
clock=clock+120
f,e,c=timeout:checkpoint()
assert(f==nil and c=="DEADLINE_EXCEEDED")
local _,res=timeout:finish()
assert(res.status=="TIMEOUT")
local cancelSession=assert(guard.create({now=now,sleep=sleep,cancelled=function()return cancel end}))
cancel=true
f,e,c=cancelSession:step("read",function() error("must not run") end)
assert(f==nil and c=="CANCELLED")
cancel=false
assert(cancelSession:finish())
local badCancel=assert(guard.create({now=now,sleep=sleep,
  cancelled=function() error("SECRET") end}))
f,e,c=badCancel:checkpoint()
assert(f==nil and c=="CANCEL_UNKNOWN")
privateReport(badCancel:snapshot())
assert(badCancel:finish())

local limit=assert(guard.create({now=now,sleep=sleep,max_steps=1}))
assert(limit:step("read",function()return true end))
f,e,c=limit:step("read",function()return true end)
assert(f==nil and c=="STEP_LIMIT")
assert(limit:finish())
local broken=assert(guard.create({now=now,sleep=sleep}))
assert(broken:defer("finalize_fail",function()error("SECRET") end))
local ran,err,code,report=broken:run(function(sess)
  local got=assert(sess:step("read",function()return 123 end))
  return "SECRET result is not a report"
end)
assert(ran==nil and code=="CLEANUP_FAILED")
privateReport(report)
assert(report.cleanup_failures==1 and report.closed)

local happy,metadata,payload=guard.run(function(sess)
  local good,read=sess:step("read",function()return 789 end)
  assert(good and read==789)
  assert(sess:defer("release",function() return true end))
  return "unlogged result"
end,{now=now,sleep=sleep})
assert(happy and metadata.status=="FINISHED" and payload=="unlogged result")
privateReport(metadata.summary)

local exception,why,kind,report2=guard.run(function(sess)
  sess:defer("end",function()return true end)
  error("SECRET exception should never log")
end,{now=now,sleep=sleep})
assert(exception==nil and kind=="CALLBACK_EXCEPTION")
privateReport(report2)
local invalid,_,code2=guard.create({max_steps=0,now=now,sleep=sleep})
assert(invalid==nil and code2~="OK")
print(("[NKRUNTIME089][HOST] PASS steps=%d callbacks=%d cleanup=%d deadline=guarded privacy=redacted"):format(
  summary.steps,callbacks,#cleanupOrder))
