from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LuaCoreReliabilityTests(unittest.TestCase):
    def test_springboard_backend_is_bounds_checked_and_retains_ipc(self):
        src = (ROOT / "patches/NKColorPickerSafe.xm").read_text()
        for marker in (
            "getRGBFromRawData", "searchRGBFromRawData",
            "colorAtPositionFromCGImage", "searchRGBFromCGImageRef",
            "NKColorParseNumber", "CGImageGetWidth", "CGImageGetHeight",
            "NKColorCopyPixels", "CGImageCreateWithImageInRect",
            "CGBitmapContextCreate", "CGColorSpaceRelease",
            "CGContextRelease", "CGImageRelease",
            "COLOR_INVALID_COORDINATES", "COLOR_OUT_OF_BOUNDS",
            "COLOR_CAPTURE_FAILED", "COLOR_BUFFER_FAILED",
            "COLOR_INVALID_RGB_RANGE", "COLOR_PIXEL_READ_FAILED",
            "return found ?: @\"-1;;-1;;-1;;-1;;-1\"",
        ):
            self.assertIn(marker, src)
        self.assertNotIn("CGImageRelease(NULL)", src)
        self.assertIn("NK_COLOR_SCAN_MAX_BYTES", src)
        self.assertIn("CGImageGetWidth(image)", src)
        self.assertIn("max(0", (ROOT / "lua/nktouch.lua").read_text())

    def test_core_prevents_invalid_color_values_and_stuck_swipes(self):
        core = (ROOT / "runtime/nkcore.c").read_text()
        self.assertIn("invalid color reply (RGB outside 0..255)", core)
        self.assertIn("invalid findColor reply", core)
        self.assertIn("if (x == -1 && y == -1)", core)
        self.assertIn("r < 0 || r > 255", core)
        self.assertIn("release_error", core)
        self.assertIn("return push_error(L, \"color not found\")", core)
        self.assertIn("M.COLOR_VERSION", (ROOT / "lua/nktouch.lua").read_text())

    def test_packaging_retains_v6_and_uses_safe_backend(self):
        prepare = (ROOT / "scripts/prepare-v077-lua-core-reliability.sh").read_text()
        self.assertIn("prepare-v076-gesture-engine.sh", prepare)
        self.assertIn('install -m 0644 "$ROOT/patches/NKColorPickerSafe.xm" "$COLOR"', prepare)
        self.assertIn("Version: 0.7.7", prepare)
        self.assertIn("function M.matchColor", prepare)
        self.assertIn("function M.waitColorMatch", prepare)
        self.assertIn("test ! -e", prepare)
        api = (ROOT / "runtime/nktouch-api.tsv").read_text()
        self.assertIn("nk.matchColor|", api)
        self.assertIn("nk.waitColorMatch|", api)

    @unittest.skipUnless(shutil.which("lua"), "host Lua required")
    def test_live_lua_api_contract_with_fake_native_color_core(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "testcolor.lua"
            p.write_text(r'''
local now=0
local calls=0
local core = {DIRECT=true, VERSION="0.6.3"}
core.nowMs=function() return now end
core.sleep=function(ms) now=now+ms; return true end
core.getColor=function(x,y)
  if x==999 then return {red=999,green=2,blue=3} end
  if x==998 then return nil,"connection refused" end
  return {red=252, green=79, blue=35, packed=252*65536+79*256+35}
end
core.findColor=function(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip)
  assert(x==100 and y==200 and w==300 and h==400 and skip==0)
  assert(rmin==245 and rmax==255 and gmin==70 and gmax==90)
  assert(bmin==30 and bmax==50)
  calls=calls+1
  if calls<3 then return nil,"color not found" end
  return {x=170,y=240,red=252,green=79,blue=35}
end
package.loaded["nkcore"]=core
local nk=assert(dofile(arg[1]))
assert(nk.COLOR_VERSION=="0.7.7")
local yes,c=nk.matchColor(100,200,255,80,40,10)
assert(yes==true and c.red==252)
local no,actual=nk.matchColor(100,200,255,80,40,2)
assert(no==false and actual.blue==35)
local bad,why,code=nk.matchColor(100,200,256,80,40,1)
assert(bad==nil and code=="INVALID" and why)
local bad2,why2,code2=nk.matchColor(-1,200,255,80,40,1)
assert(bad2==nil and code2=="INVALID")
local bad3,_,code3=nk.matchColor(999,200,255,80,40,10)
assert(bad3==nil and code3=="CORE")
local hit=assert(nk.waitColorMatch(255,80,40,10,{x=100,y=200,w=300,h=400},5000))
assert(hit.x==170 and hit.y==240 and calls==3 and now==400)
local failed,why4,code4=nk.waitColorMatch(255,80,40,10,{x=100,y=200,w=0,h=400},5000)
assert(failed==nil and code4=="INVALID" and why4)
local transport,err,kind=nk.matchColor(998,200,255,80,40,10)
assert(transport==nil and kind=="CONNECT" and err)
print("Lua Color API PASS")
''')
            run = subprocess.run(["lua", str(p), str(ROOT / "lua/nktouch.lua")],
                                 capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
