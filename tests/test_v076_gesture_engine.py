from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GESTURE = ROOT / "lua/nkgesture_v6.lua"


def event(kind, finger, x, y):
    return f"101{kind}{finger:02d}{round(x * 10):05d}{round(y * 10):05d}"


class RecorderV6Contract(unittest.TestCase):
    def test_native_path_is_bounded_continuous_touch(self):
        src = (ROOT / "runtime/nkcore.c").read_text()
        self.assertIn("static int l_path(lua_State *L)", src)
        self.assertIn("NK_PATH_MAX_POINTS 256", src)
        self.assertIn('{"path", l_path}', src)
        self.assertIn("TOUCH_DOWN, points[0].x", src)
        self.assertIn("TOUCH_UP : TOUCH_MOVE", src)
        self.assertIn("path timestamps must increase from zero", src)
        self.assertIn("Best effort release", src)
        self.assertIn("function M.path(points)", (ROOT / "lua/nktouch.lua").read_text())
        self.assertIn("native continuous path playback unavailable", (ROOT / "lua/nktouch.lua").read_text())

    def test_staged_layer_preserves_v5_and_v0756(self):
        prepare = (ROOT / "scripts/prepare-v076-gesture-engine.sh").read_text()
        apply = (ROOT / "scripts/apply-v076-gesture-engine.py").read_text()
        self.assertIn("prepare-v0756-control-foundation.sh", prepare)
        self.assertIn("VERSION", prepare)
        self.assertIn("test ! -e", prepare)
        self.assertIn("local gesture = dofile(", apply)
        self.assertIn("local function trim_tail(path, count)", prepare)
        self.assertIn("row.path = ", apply)
        self.assertIn("PACKAGE_VERSION", apply)
        self.assertIn("0.7.5.6", (ROOT / "runtime/nktouchctl-v7").read_text())

    @unittest.skipUnless(shutil.which("lua"), "host Lua 5.4 runtime required")
    def test_real_hid_paths_and_legacy_timelines(self):
        with tempfile.TemporaryDirectory() as folder:
            d = Path(folder)
            raw = d / "sample.raw"
            timeline = d / "sample.nktl"
            script = d / "sample.lua"
            raw.write_text("\n".join([
                event(1, 1, 100, 200), "18120000", event(0, 1, 100, 200),
                "18200000", event(1, 1, 120, 240), "18600000",
                event(0, 1, 120, 240),
                "18100000", event(1, 1, 100, 500), "1860000",
                event(2, 1, 140, 475), "1860000",
                event(2, 1, 200, 440), "1860000",
                event(0, 1, 260, 420),
                "18150000", event(1, 1, 310, 710), "18200000",
                event(2, 1, 330, 665), "18600000", event(0, 1, 400, 630),
                ""
            ]))
            test_lua = d / "test.lua"
            test_lua.write_text(
                "local g=dofile(arg[1])\n"
                "local rows,ignored=g.parseRaw(arg[2]); assert(rows and #rows==4, ignored)\n"
                "assert(rows[1].action=='tap')\n"
                "assert(rows[2].action=='hold')\n"
                "assert(rows[3].action=='swipe' and rows[4].action=='drag')\n"
                "assert(rows[3].idle_ms>0 and rows[4].duration_ms>=600)\n"
                "local pts=assert(g.decodePath(rows[3].path,rows[3].duration_ms))\n"
                "assert(#pts==4 and pts[1].t==0 and pts[4].t==rows[3].duration_ms)\n"
                "assert(g.writeTimeline(arg[3],rows,'hid',ignored))\n"
                "local loaded=assert(g.readTimeline(arg[3]));assert(#loaded==4 and loaded[3].path~='')\n"
                "assert(g.renderLua(arg[3],arg[4]))\n"
                "local f=assert(io.open(arg[4])); local src=f:read('*a');f:close()\n"
                "assert(src:find('nk.path(',1,true) and src:find('nk.hold(',1,true))\n"
                "local legacy=arg[3]..'.legacy'\n"
                "local lf=assert(io.open(legacy,'w'))\n"
                "lf:write('1\\tswipe\\t0\\t250\\t100.0\\t100.0\\t300.0\\t300.0\\t01\\t2\\n');lf:close()\n"
                "local old=assert(g.readTimeline(legacy));assert(old[1].path=='')\n"
                "assert(g.renderLua(legacy,arg[4]));local out=assert(io.open(arg[4])):read('*a')\n"
                "assert(out:find('nk.swipe(',1,true))\n"
                "local bad=arg[3]..'.bad';local bf=assert(io.open(bad,'w'))\n"
                "bf:write('1\\tswipe\\t0\\t50\\t0\\t0\\t100\\t100\\t01\\t3\\t0,0,0;1,1,10;2,2,5\\n');bf:close()\n"
                "local invalid,err=g.readTimeline(bad);assert(not invalid and err)\n"
                "print('PASS gesture path + legacy + malformed tests')\n"
            )
            run = subprocess.run(
                ["lua", str(test_lua), str(GESTURE), str(raw), str(timeline), str(script)],
                capture_output=True, text=True, timeout=15
            )
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    @unittest.skipUnless(shutil.which("lua"), "host Lua 5.4 runtime required")
    def test_overlapping_fingers_are_not_faked_as_sequential_swipes(self):
        with tempfile.TemporaryDirectory() as folder:
            raw = Path(folder) / "overlap.raw"
            raw.write_text("\n".join([
                event(1, 1, 100, 100), "1810000",
                event(1, 2, 200, 200), "1810000",
                event(0, 1, 110, 110), "1810000",
                event(0, 2, 210, 210), ""
            ]))
            p = Path(folder) / "overlap.lua"
            p.write_text("local g=dofile(arg[1]);local rows,ignored=g.parseRaw(arg[2]);"
                         "assert(rows and #rows==0 and ignored>=2)\n")
            run = subprocess.run(["lua", str(p), str(GESTURE), str(raw)],
                                 capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
