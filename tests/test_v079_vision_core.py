from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class VisionCoreContract(unittest.TestCase):
    def test_opt_in_vision_preserves_old_lua_api(self):
        old=(ROOT/"lua/nktouch.lua").read_text()
        for marker in ("function M.getColor", "function M.findColor",
                       "function M.findImage", "function M.ocr", "function M.screenshot",
                       "function M.captureFrame", "function M.withFrame",
                       'M.COLOR_VERSION="0.7.7"', 'M.VISION_VERSION="0.7.9"'):
            self.assertIn(marker,old)
        self.assertIn("return M",old)
        frame=(ROOT/"lua/nkvision.lua").read_text()
        for marker in ("pcall(nk.screenshot, path)", "pcall(native.open, path)",
                       "pcall(os.remove, path)", "native.tempPath",
                       "pcall(frame.close, frame)",
                       "function M.withFrame", "return table.unpack"):
            self.assertIn(marker,frame)

    def test_native_image_ocr_and_memory_bounds(self):
        native=(ROOT/"runtime/nkvision.m").read_text()
        for marker in ("luaopen_nkvision_native", "NV_MAX_BITMAP",
                       "NV_MAX_FILE", "NV_MAX_TEMPLATE", "NV_MAX_MATCH_EVAL",
                       "CGImageSourceCreateWithData", "CGImageSourceCreateWithURL",
                       "CGBitmapContextCreate", "CFRelease(f->jpeg)",
                       "CGImageRelease(f->image)", "free(f->gray)",
                       'lua_setfield(L,-2,"packed")', "VNRecognizeTextRequest",
                       "VNImageRequestHandler", "nv_find_image",
                       "nv_get_color", "nv_find_color", "nv_ocr", "nv_close",
                       "mkstemps(path,4)", "budget--", "gridTarget",
                       'return nv_error(L,"color not found in captured frame","NOT_FOUND")'):
            self.assertIn(marker,native)
        self.assertNotIn("createScreenShotCGImageRef",native)
        self.assertNotIn("performTouch",native)
        self.assertNotIn("CAPTURE_SCREEN",native)

    def test_build_staging_and_rootless_compat(self):
        stage=(ROOT/"scripts/prepare-v079-vision-core.sh").read_text()
        build=(ROOT/".github/workflows/build-v079-vision-core.yml").read_text()
        for marker in ("prepare-v0781-core-selftest-hotfix.sh",
                       "install -m 0644", "Version: 0.7.9",
                       "PACKAGE_VERSION", "vision-selftest)",
                       "nkvision_selftest.lua", "NKHotkeyActionRecorderFinish",
                       "test ! -e"):
            self.assertIn(marker,stage)
        for marker in ("runtime/nkvision.m", "runtime/nkvision.o",
                       "nkvision_native", "luaopen_nkvision_native",
                       "-framework Vision", "-framework ImageIO",
                       "prepare-v079-vision-core.sh", "test_v079_vision_core.py",
                       "NK_VERSION: 0.7.9", "NK_BUILD: 7900"):
            self.assertIn(marker,build)
        self.assertNotIn("publish-sileo:",build)

    @unittest.skipUnless(shutil.which("lua"),"host Lua unavailable")
    def test_mock_capture_once_reuse_frame_close_and_failure(self):
        source=r'''
local lib=arg[1]
package.path=lib.."/?.lua;"..package.path
local nv=require("nkvision")
local shots,opens,closes,removes=0,0,0,0
local realRemove=os.remove
os.remove=function(p)
  removes=removes+1
  assert(p:find("vision%-") and p:find(".jpg",1,true))
  return true
end
local nativeFrame={}
function nativeFrame:info() return {width=120,height=200,immutable=true,bytes=1234} end
function nativeFrame:getColor(x,y)
  assert(x==60 and y==100)
  return {red=13,green=14,blue=15,packed=13*65536+14*256+15}
end
function nativeFrame:findColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip)
  assert(x==60 and y==100 and w==1 and h==1 and skip==0)
  assert(rmin==13 and rmax==13 and gmin==14 and gmax==14)
  return {x=x,y=y,red=13,green=14,blue=15}
end
function nativeFrame:close() closes=closes+1;return true end
package.loaded["nkvision_native"]={
  tempPath=function() return "/var/mobile/Library/NKTouch/vision-abc123.jpg" end,
  open=function(path)
    opens=opens+1
    return nativeFrame
  end
}
local nk={screenshot=function(path)
  shots=shots+1
  return path
end}
local v,e,k=nv.withFrame(nk,function(frame)
  local c=frame:getColor(60,100)
  local found=frame:findColor(60,100,1,1,13,13,14,14,15,15,0)
  assert(c.red==found.red)
  return c.packed,"ok",false
end)
assert(v==13*65536+14*256+15 and e=="ok" and k==false)
assert(shots==1 and opens==1 and closes==1 and removes==1)
local result,err,code=nv.withFrame(nk,function(frame)
  error("callback failure")
end)
assert(result==nil and code=="CALLBACK" and err:find("callback failure"))
assert(shots==2 and opens==2 and closes==2 and removes==2)
package.loaded["nkvision_native"]={
  tempPath=function() return "/var/mobile/Library/NKTouch/vision-def123.jpg" end,
  open=function(path) return nil,"bad JPEG","DECODE" end
}
local frame,err,code=nv.capture(nk)
assert(frame==nil and err=="bad JPEG" and code=="DECODE")
assert(shots==3 and removes==3)
nk.screenshot=function()return nil,"offline","CONNECT"end
local frame,err,code=nv.capture(nk)
assert(frame==nil and code=="CONNECT")
assert(shots==3 and removes==4)
nk.screenshot=function()error("backend panic")end
local frame,err,code=nv.capture(nk)
assert(frame==nil and code=="CAPTURE" and err:find("backend panic"))
assert(removes==5)
nk.screenshot=function()return "/var/mobile/wrong.jpg"end
local frame,err,code=nv.capture(nk)
assert(frame==nil and code=="CAPTURE")
assert(removes==6)
package.loaded["nkvision_native"]={
  tempPath=function()return nil,"no directory","FRAME_IO"end,
  open=function()error("never open")end
}
local frame,err,code=nv.capture(nk)
assert(frame==nil and code=="FRAME_IO")
assert(removes==6)

os.remove=realRemove
print("[HOST][VISION] PASS")
'''
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"verify.lua"
            path.write_text(source)
            r=subprocess.run(["lua",str(path),str(ROOT/"lua")],
                             capture_output=True,text=True,timeout=12)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("[HOST][VISION] PASS",r.stdout)

if __name__=="__main__":
    unittest.main()
