-- NKTouch v0.7.16: host tests for JSON, HTTP argument guards, Input Engine v2.
-- No iPhone, network, clipboard or real keyboard side effects.
package.path="lua/?.lua;"..package.path

local count=0
local function check(ok,label)
  assert(ok,label)
  count=count+1
end

local json=require("nkjson")
local encoded,err=json.encode({hello="Xin chào 😀",enabled=true,count=12,
                               items=json.array({"a","b"}),none=json.null})
check(type(encoded)=="string" and not err,"JSON encode")
local decoded,derr=json.decode(encoded)
check(decoded and not derr and decoded.hello=="Xin chào 😀"
   and decoded.enabled==true and decoded.count==12
   and decoded.items[2]=="b" and decoded.none==json.null,"JSON decode Unicode")
local emptyArray=assert(json.encode(json.array({})))
local emptyObject=assert(json.encode(json.object({})))
check(emptyArray=="[]" and emptyObject=="{}","JSON empty array/object")
local v,e=json.decode('{"broken":')
check(v==nil and type(e)=="string","JSON invalid payload")
local circular={};circular.self=circular
local c,cerr=json.encode(circular)
check(c==nil and type(cerr)=="string","JSON reject circular table")
local nul,nerr=json.decode('{"value":null}')
check(nul and nul.value==json.null and not nerr,"JSON null sentinel")

local net=require("nknet")
local origExecute=os.execute
os.execute=function()error("unsafe network/helper invocation from invalid request")end
local function badNetwork(label,fn)
  local ok,result,err,kind=pcall(fn)
  check(ok and result==nil and kind=="INVALID" and type(err)=="string",label)
end
badNetwork("HTTP reject file URL",function()
  return net.request({url="file:///etc/passwd"})
end)
badNetwork("HTTP reject unsupported method",function()
  return net.request({method="CONNECT",url="https://example.com"})
end)
badNetwork("HTTP reject zero timeout",function()
  return net.request({url="https://example.com",timeout_ms=0})
end)
badNetwork("HTTP GET invalid URL",function()
  return net.get("not-a-url")
end)
badNetwork("HTTP POST invalid URL",function()
  return net.post("not-a-url",{ok=true})
end)
badNetwork("HTTP download invalid URL",function()
  return net.download("not-a-url","/tmp/test")
end)
badNetwork("HTTP upload invalid URL",function()
  return net.upload("not-a-url","/tmp/test")
end)
os.execute=origExecute

local input=require("nkinput_v2")
local dispatched=0
local lastMode
local mock={
  _inputNativeV2=function(text,mode)
    dispatched=dispatched+1
    lastMode=mode
    return true
  end,
  ocr=function() return "Xin chào 😀" end,
  sleep=function()return true end,
}
local ok,meta=input.input(mock,"Xin chào 😀\nL2;;OK")
check(ok and meta.sent and meta.verified==false and meta.status=="dispatched"
    and dispatched==1 and lastMode=="direct","Input UTF-8 safe single dispatch")
ok,meta=input.input(mock,"hello",{mode="keyboard"})
check(ok and dispatched==2 and lastMode=="keyboard","Input explicit keyboard")
local s,sErr,sCode=input.input(mock,"")
check(s==nil and sCode=="INVALID" and dispatched==2,"Input rejects empty")
s,sErr,sCode=input.input(mock,"contains\0NUL")
check(s==nil and sCode=="INVALID" and dispatched==2,"Input rejects NUL")
s,sErr,sCode=input.input(mock,string.rep("x",8193))
check(s==nil and sCode=="INVALID" and dispatched==2,"Input 8192-byte limit")
s,sErr,sCode=input.password(mock,"MySecret!",{verify={x=0,y=0,w=20,h=20}})
check(s==nil and sCode=="SECURE" and dispatched==2,"Password OCR forbidden")
local okpwd,pwdmeta=input.password(mock,"MySecret!")
check(okpwd and pwdmeta.sent and dispatched==3,"Password dispatched once")
local nop={
  _inputNativeV2=function()
    dispatched=dispatched+1
    return nil,"socket timeout","CONNECT"
  end
}
local failed,msg,kind=input.input(nop,"hello")
check(failed==nil and kind=="CONNECT" and dispatched==4,
      "Input fail without automatic duplicate retry")
local verify={verify={x=0,y=0,w=50,h=30,expected="Xin chào 😀"}}
local vOk,vMeta=input.input(mock,"Xin chào 😀",verify)
check(vOk and vMeta.verified and dispatched==5,"Input optional OCR verification")
print(("[NKCMD][PURE] PASS assertions=%d (no real HTTP or keyboard)"):format(count))
