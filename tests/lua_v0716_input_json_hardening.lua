-- NKTouch v0.7.16 dev: Vietnamese Unicode Input + JSON robustness.
-- Host-only. No native keyboard, external network or live credentials.
package.path="lua/?.lua;"..package.path
local input=require("nkinput_v2")
local json=require("nkjson")
local n=0
local function check(condition,msg) assert(condition,msg);n=n+1 end
local function invalid(value,err,code,expected)
  check(value==nil and code==expected and type(err)=="string",expected.." expected")
end
local sent,keyboard=0,nil
local nk={_inputNativeV2=function(text,mode)
  sent=sent+1
  keyboard=mode
  return true
end, sleep=function()return true end,
ocr=function()return "Đã nhập: Xin chào Việt Nam 👋"end}
local good,meta=input.input(nk,"Xin chào Việt Nam 👋\n;;")
check(good and meta.sent and not meta.verified and sent==1 and keyboard=="direct","Unicode/special separators")
good,meta=input.input(nk,"Tiếng Việt",{mode="keyboard"})
check(good and keyboard=="keyboard" and sent==2,"keyboard mode")
local decomposed="Tiếng Việt"
good,meta=input.input(nk,decomposed)
check(good and sent==3,"decomposed combining UTF-8")
good,meta=input.input(nk,string.rep("a",8192))
check(good and sent==4,"8192 boundary")
invalid(input.input(nk,string.rep("a",8193)),"INVALID")
check(sent==4,"8193 must not dispatch")
invalid(input.input(nk,"bad\255"),"INVALID")
check(sent==4,"invalid UTF-8 no dispatch")
invalid(input.input(nk,"hello",{verify={x=0,y=0,w=100,h=60,expected="bad\255"}}),"INVALID")
invalid(input.input(nk,"hello",{verify={x=0,y=0,w=100,h=60,language="en\n-US"}}),"INVALID")
check(sent==4,"bad OCR preflight no dispatch")
local brokenNative={_inputNativeV2=function()
 sent=sent+1
 error("device disconnected midway")
end}
local v,e,c=input.input(brokenNative,"A")
invalid(v,e,c,"DISPATCH_UNCERTAIN")
check(sent==5,"thrown native dispatch must never retry")
local brokenOCR={_inputNativeV2=function()sent=sent+1;return true end,
  ocr=function()error("Vision service crash")end}
local result,err,code,info=input.input(brokenOCR,"A",
  {verify={x=0,y=0,w=100,h=50},settleMs=0})
invalid(result,err,code,"UNVERIFIED")
check(info.sent and not info.verified and sent==6,"OCR exception after send: no retype")
local brokenSleep={_inputNativeV2=function()sent=sent+1;return true end,
 sleep=function()error("sleep interrupted")end,
 ocr=function()error("must not OCR before settling")end}
result,err,code,info=input.input(brokenSleep,"A",
  {verify={x=0,y=0,w=100,h=50},settleMs=200})
invalid(result,err,code,"UNVERIFIED")
check(sent==7 and info.sent,"settle failure must not send again")
local passwd={_inputNativeV2=function()sent=sent+1;return true end}
result,err,code=input.password(passwd,"dummy-secret",{
 verify={x=0,y=0,w=40,h=30}})
invalid(result,err,code,"SECURE")
check(sent==7,"password OCR rejected before dispatch")
good,meta=input.password(passwd,"dummy-secret")
check(good and meta.sent and sent==8,"password single dispatch")

local data={text="Xin chào 🌻",list=json.array({1,2,3}),yes=true,
  nothing=json.null}
local encoded=assert(json.encode(data))
local decoded=assert(json.decode(encoded))
check(decoded.text==data.text and decoded.list[3]==3 and decoded.nothing==json.null,"UTF8 JSON roundtrip")
check(assert(json.encode(json.array({})))=="[]","explicit empty array")
check(assert(json.encode(json.object({})))=="{}","explicit empty object")
local function rejectedJson(source,needle)
  local result,msg=json.decode(source)
  check(result==nil and type(msg)=="string" and msg:find(needle,1,true)~=nil,
        "JSON must reject: "..needle)
end
rejectedJson('{"a":1,"a":2}',"duplicate")
rejectedJson('{"a":null,"a":0}',"duplicate")
rejectedJson('{"a":1e9999}',"non-finite")
rejectedJson('{"bad\255":"x"}',"UTF-8")
rejectedJson('{"a":1}\255',"UTF-8")
local bad,why=json.encode({x="bad\255"})
check(bad==nil and why:find("UTF-8"),"invalid UTF8 encoder input")
local large,lim=json.decode(string.rep(" ",16*1024*1024+1))
check(large==nil and lim:find("limit"),"JSON bounded read")
print(("[NKQA][INPUT_JSON] PASS checks=%d dispatches=%d no automatic replay"):format(n,sent))
