"""Native nkcore (Linux host build only; never packages an iOS .deb).

The test proves malformed endpoints are refused BEFORE any touch TCP socket.
It does not claim gestures work correctly on an iPhone.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
NATIVE=ROOT/"runtime/nkcore.c"

class NKCoreNativePreflight(unittest.TestCase):
    def test_source_preflights_both_swipe_endpoints(self):
        src=NATIVE.read_text()
        start=src.index("static int l_swipe(lua_State *L)")
        stop=src.index("static int l_open_app(lua_State *L)",start)
        part=src[start:stop]
        for token in ("coord(x1,&sx1)","coord(y1,&sy1)","coord(x2,&sx2)",
                      "coord(y2,&sy2)","invalid swipe endpoint coordinates",
                      "TOUCH_DOWN","TOUCH_UP"):
            self.assertIn(token,part)
        self.assertLess(part.index("coord(x2,&sx2)"),part.index("connect_core("))
        self.assertLess(part.index("coord(y2,&sy2)"),part.index("connect_core("))
        self.assertLess(part.index("connect_core("),part.index("touch_packet(fd, TOUCH_DOWN"))

    def test_native_image_match_reply_rejects_nonfinite_and_no_match(self):
        src=NATIVE.read_text()
        start=src.index("static int l_find_image(lua_State *L)")
        stop=src.index("static int l_get_color(lua_State *L)",start)
        part=src[start:stop]
        for token in ("!isfinite(x)","!isfinite(y)","!isfinite(w)","!isfinite(h)",
                      "x == -1 && y == -1","image not found",
                      "rectangle out of range"):
            self.assertIn(token,part)

    @unittest.skipUnless(all(shutil.which(x) for x in
                        ("gcc","lua","pkg-config")),
                         "host compiler/Lua not installed")
    def test_native_module_refuses_invalid_coordinates_offline(self):
        flags=subprocess.run(["pkg-config","--cflags","--libs","lua5.4"],
                             capture_output=True,text=True)
        if flags.returncode!=0:
            self.skipTest("liblua5.4-dev missing")
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/"nkcore.so"
            args=["gcc","-shared","-fPIC","-O2","-Wall","-Wextra","-Werror",
                  str(NATIVE),"-o",str(out)]+flags.stdout.strip().split()
            c=subprocess.run(args,capture_output=True,text=True,timeout=35)
            self.assertEqual(c.returncode,0,c.stdout+c.stderr)
            harness=Path(tmp)/"run.lua"
            harness.write_text(r'''
package.cpath=arg[1].."/?.so;"..package.cpath
local core=require("nkcore")
local function rejected(name,...)
 local value,err=core[name](...)
 assert(value==nil and type(err)=="string",
        name.." malformed coordinates were not rejected")
 assert(err:find("invalid") or err:find("coordinate"),err)
end
-- These MUST NOT attempt connect_core/TOUCH_DOWN, because no iOS
-- controller exists in this host environment.
rejected("tap",-1,200)
rejected("tap",math.huge,200)
rejected("tap",750,0/0)
rejected("swipe",100,100,10000,200,400)
rejected("swipe",100,100,-1,200,400)
rejected("swipe",100,100,200,math.huge,400)
rejected("swipe",100,100,0/0,200,400)
local ok=pcall(core.path,{{x=0,y=0,t=0},{x=10000,y=20,t=10}})
assert(not ok,"native path must reject invalid points before network")
print("[NKCORE][NATIVE_PREFLIGHT] PASS invalid touch args never sent")
''')
            run=subprocess.run(["lua",str(harness),tmp],
                            capture_output=True,text=True,timeout=10)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            self.assertIn("NATIVE_PREFLIGHT",run.stdout)

if __name__=="__main__":
    unittest.main()
