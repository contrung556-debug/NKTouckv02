"""Vision native RAM and Lua GC regression tests (dev only, no iOS build)."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class VisionMemory(unittest.TestCase):
    def test_native_bitmap_is_lazy_and_released(self):
        s=(ROOT/"runtime/nkvision.m").read_text()
        open_body=s.split("static int nv_open(lua_State *L)",1)[1].split(
            "static int nv_info(lua_State *L)",1)[0]
        image_body=s.split("static int nv_find_image(lua_State *L)",1)[1].split(
            "static const luaL_Reg nv_methods",1)[0]
        self.assertIn("f->rgba=NULL; f->gray=NULL;",open_body)
        self.assertNotIn("nv_decoded(img",open_body)
        self.assertIn("static int nv_ensure_rgba(NVFrame *f)",s)
        self.assertIn("if (!nv_ensure_rgba(f))",s)
        self.assertNotIn("malloc(w*h)",open_body)
        self.assertIn("static int nv_ensure_gray(NVFrame *f)",s)
        self.assertIn("if (f->gray) return 1;",s)
        self.assertIn("if (!nv_ensure_gray(f))",image_body)
        self.assertIn('lua_setfield(L,-2,"gray_bytes")',s)
        self.assertIn("if (f->gray) { free(f->gray); f->gray = NULL; }",s)
        self.assertIn("if (f->rgba) { free(f->rgba); f->rgba = NULL; }",s)
        self.assertIn("if (f->image) { CGImageRelease(f->image);",s)

    def test_lua_withframe_always_closes_before_incremental_gc(self):
        s=(ROOT/"lua/nkvision.lua").read_text()
        a=s.index("local closeOk, closeResult = pcall(frame.close, frame)")
        b=s.index('pcall(collectgarbage, "step", 64)',a)
        self.assertLess(a,b)
        self.assertIn('if not values[1] then return nil, tostring(values[2]), "CALLBACK"',s)
        self.assertIn("local removed, removeErr = cleanup(path)",s)

    @unittest.skipUnless(shutil.which("lua"),"host Lua 5.4 required")
    def test_lua_gc_helper_releases_only_lua_heap(self):
        harness=r'''
package.path="lua/?.lua;"..package.path
local memory=require("nkmemory")
local before=assert(memory.stats())
assert(before.scope=="LUA_HEAP_AND_OPTIONAL_PROCESS_RSS" and not before.process_rss_available)
local chunks={}
for i=1,3000 do chunks[i]={value=("abc"..i):rep(30)} end
local held=assert(memory.stats())
assert(held.lua_kb>before.lua_kb)
chunks=nil
local partial=assert(memory.release({mode="step",step_kb=128}))
assert(partial.scope=="LUA_HEAP_AND_OPTIONAL_PROCESS_RSS" and partial.mode=="step")
local full=assert(memory.release({mode="full"}))
assert(full.mode=="full")
assert(full.lua_kb_after < held.lua_kb,"Lua heap was not reclaimed")
local invalid,_,code=memory.release({mode="kernel-kill"})
assert(invalid==nil and code=="INVALID")
invalid,_,code=memory.release({mode="step",step_kb=-100})
assert(invalid==nil and code=="INVALID")
print("[NKLAB][MEMORY] LUA_HEAP_GC_PASS")
'''
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"gc_test.lua"
            path.write_text(harness)
            r=subprocess.run(["lua",str(path)],cwd=ROOT,timeout=12,
                             capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("LUA_HEAP_GC_PASS",r.stdout)

    @unittest.skipUnless(shutil.which("lua"),"host Lua 5.4 required")
    def test_many_frames_close_native_memory_without_temp_leaks(self):
        script=r'''
package.path="lua/?.lua;"..package.path
local v=require("nkvision")
local calls,closes=0,0
local root=assert(arg[1])
package.preload.nkvision_native=function()
  return {
    tempPath=function()
      calls=calls+1
      local name=root.."/snapshot"..calls..".jpg"
      local f=assert(io.open(name,"wb"));f:close()
      return name
    end,
    open=function(path)
      local f=assert(io.open(path,"rb"));f:close()
      local frame={closed=false,blob=string.rep("X",16384)}
      function frame:close()
        assert(not self.closed)
        self.blob=nil
        self.closed=true
        closes=closes+1
        return true
      end
      function frame:info()return {width=750,height=1334} end
      return frame
    end
  }
end
local nk={screenshot=function(path)
  local f=assert(io.open(path,"wb"))
  f:write("SAMPLE");f:close()
  return path
end}
for i=1,120 do
  local ret
  if i%7==0 then
    local result,err,code=v.withFrame(nk,function(frame)
      assert(frame:info().height==1334)
      error("simulated callback failure")
    end)
    assert(result==nil and code=="CALLBACK")
  else
    ret=v.withFrame(nk,function(frame)
      assert(frame:info().width==750)
      return true
    end)
    assert(ret==true)
  end
  local file=io.open(root.."/snapshot"..i..".jpg","rb")
  assert(file==nil,"Vision leaked screenshot path")
end
assert(calls==120 and closes==120)
collectgarbage("collect")
print("[NKLAB][MEMORY] FRAMES_120_CLOSED")
'''
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"test.lua";path.write_text(script)
            r=subprocess.run(["lua",str(path),d],cwd=ROOT,
               timeout=15,capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("FRAMES_120_CLOSED",r.stdout)

if __name__=="__main__":
    unittest.main()
