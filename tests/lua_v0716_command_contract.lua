-- Run with Lua 5.4: lua tests/lua_v0716_command_contract.lua
-- Self-contained mocks: no SpringBoard, no touch, no real network.
package.path="lua/?.lua;"..package.path
local contract=require("nkcommand_contract")
local names={"tap","hold","swipe","sleep","openApp","waitApp","moveCursor","delete",
  "getColor","findColor","waitColor","tapColor","findImage","waitImage",
  "tapImage","ocr","waitText","screenshot","status","toast"}
local calls={}
local api={inputText=function(text) return text end}
for _,name in ipairs(names) do
  calls[name]=0
  api[name]=function(...)
    calls[name]=calls[name]+1
    return true, {...}
  end
end
assert(contract.install(api)==api)
assert(api.COMMAND_CONTRACT_VERSION=="0.7.16-dev")

local tested=0
local function valid(name,...)
  local before=calls[name]
  local ok,params=api[name](...)
  assert(ok==true, name.." valid command rejected: "..tostring(params))
  assert(calls[name]==before+1,name.." did not dispatch exactly once")
  tested=tested+1
end
local function invalid(name,...)
  local before=calls[name]
  local value,err,kind=api[name](...)
  assert(value==nil and kind=="INVALID" and type(err)=="string",name.." invalid call accepted")
  assert(calls[name]==before,name.." sent an unsafe command")
  tested=tested+1
end
valid("tap",120,400)
valid("tap",750.5,100.1)
invalid("tap",10000,500)
invalid("tap",0/0,200)
invalid("tap",100,math.huge)
valid("hold",120,350,500)
invalid("hold",120,350,-1)
invalid("hold",120,350,300001)
valid("swipe",100,400,100,200,400)
invalid("swipe",100,400,100,200,1)
invalid("swipe",100,400,-1,200,400)
valid("sleep",60000)
valid("sleep",0)
invalid("sleep",-1)
invalid("sleep","forever")
valid("openApp","com.apple.mobilenotes")
invalid("openApp","")
invalid("openApp","com.foo\nbar")
valid("waitApp","com.apple.mobilenotes",10000,250)
invalid("waitApp","com.apple.mobilenotes",1000,0)
invalid("waitApp","notbundle",5000,200)
valid("moveCursor",-1)
invalid("moveCursor","not a number")
valid("delete",1)
invalid("delete",-2)
valid("getColor",120,500)
invalid("getColor",120.5,500)
invalid("getColor",-1,200)
local color={100,200,20,20,0,255,25,40,128,200,0}
valid("findColor",table.unpack(color))
invalid("findColor",100,200,20,20,256,255,25,40,128,200,0)
invalid("findColor",100,200,20,20,30,20,25,40,128,200,0)
valid("waitColor",100,200,20,20,0,255,0,255,0,255,5000,200,0)
invalid("waitColor",100,200,20,20,0,255,0,255,0,255,5000,0,0)
valid("tapColor",100,200,20,20,0,255,0,255,0,255,5000,200,0)
invalid("tapColor",100,200,20,20,0,255,0,255,0,255,5000,200,1001)
valid("findImage","/var/mobile/button.png",2,0.8,0.8)
invalid("findImage","/var/mobile/button.png",9,0.8,0.8)
invalid("findImage","/var/mobile/button.png",2,1.1,0.8)
valid("waitImage","/var/mobile/button.png",5000,200,0.8)
invalid("waitImage","/var/mobile/button.png",5000,0,0.8)
valid("tapImage","/var/mobile/button.png",5000,200,0.8)
invalid("tapImage","/var/mobile/a\nb",5000,200,0.8)
valid("ocr",0,0,500,300,"en-US")
invalid("ocr",0,0,-1,300,"en-US")
invalid("ocr",0,0,500,300,"en-US;;BAD")
valid("waitText",0,0,500,300,"Continue",5000,200,"en-US")
invalid("waitText",0,0,500,300,"",5000,200,"en-US")
invalid("waitText",0,0,500,300,"Continue",5000,0,"en-US")
valid("screenshot","/var/mobile/shot.jpg")
invalid("screenshot","bad\npath")
valid("status",50,"ok")
invalid("status",102,"not ok")
valid("toast","success","done",2)
invalid("toast","success","done",61)
assert(api.inputText("Hello")=="Hello","InputText must remain untouched")
print(("[NKCMD][SUMMARY] PASS tests=%d guarded=%d side_effects_from_bad_calls=0"):format(tested,#names))
