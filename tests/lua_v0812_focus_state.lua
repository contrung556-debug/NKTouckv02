local focus=dofile("lua/nkfocus_state.lua")
local function expect(ok,msg) if not ok then error(msg or "assertion failed",2) end end
local function fixture(sequence)
  local now,index,queries=0,0,0
  local nk={focusedInput=function(bundle)
    expect(bundle=="com.example.test","bundle passed through")
    queries=queries+1
    index=math.min(index+1,#sequence)
    return sequence[index]
  end}
  return nk,function(ms) now=now+ms; return true end,function() return now end,
    function() return queries end
end
do
  local nk,sleep,clock,queries=fixture({true,true})
  local result,err,code=focus.waitFor(nk,{bundle="com.example.test",
    stable_reads=2,max_reads=4,interval_ms=100,timeout_ms=1000,
    sleep=sleep,now=clock})
  expect(result and result.status=="PASS","stable focus: "..tostring(code or err))
  expect(result.reads==2 and result.stable_reads==2,"stable read counts")
  expect(queries()==2,"read-only focus query count")
end
do
  local nk,sleep,clock=fixture({true,false,true,false})
  local result,_,code,detail=focus.waitFor(nk,{bundle="com.example.test",
    stable_reads=2,max_reads=4,interval_ms=100,timeout_ms=1000,
    sleep=sleep,now=clock})
  expect(result==nil and code=="FOCUS_UNSTABLE","unstable focus fails closed")
  expect(detail.action_taken==false,"no action on uncertainty")
end
do
  local nk,sleep,clock=fixture({nil})
  local result,_,code=focus.waitFor(nk,{bundle="com.example.test",sleep=sleep,now=clock})
  expect(result==nil and code=="FOCUS_PROBE_UNAVAILABLE","unknown focus fails closed")
end
do
  local nk,sleep,clock=fixture({true})
  local result,_,code=focus.waitFor(nk,{bundle="com.example.test",
    unknown=true,sleep=sleep,now=clock})
  expect(result==nil and code=="INVALID","reject unknown options")
end
print("[NKFOCUS812][HOST] PASS")
