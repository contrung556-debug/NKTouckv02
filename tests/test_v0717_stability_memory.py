"""NKTouch v0.7.17 regression gates. Host checks are not iPhone verification."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class StabilityMemoryV0717(unittest.TestCase):
    def test_native_ocr_filters_supported_languages_and_falls_back_in_same_frame(self):
        src=(ROOT/"runtime/nkvision.m").read_text()
        fn=src.split("static int nv_ocr(lua_State *L)",1)[1].split("static int nv_score(",1)[0]
        self.assertIn("supportedRecognitionLanguagesAndReturnError:nil",fn)
        self.assertIn("[supported containsObject:lang]",fn)
        self.assertIn("automaticallyDetectsLanguage=YES",fn)
        self.assertIn("if (!success && len)",fn)
        self.assertIn("initWithCGImage:crop",fn)
        self.assertIn("CGImageRelease(crop)",fn)
        self.assertNotIn("TASK_SCREENSHOT",fn)
        self.assertNotIn("tap(",fn)

    def test_native_process_rss_is_read_only_and_close_releases(self):
        src=(ROOT/"runtime/nkvision.m").read_text()
        fn=src.split("static int nv_memory_stats(lua_State *L)",1)[1].split(
            "static const luaL_Reg nv_module[]",1
        )[0]
        self.assertIn("mach_task_self()",fn)
        self.assertIn("MACH_TASK_BASIC_INFO",fn)
        self.assertIn('lua_setfield(L, -2, "rss_bytes")',fn)
        self.assertIn('lua_setfield(L, -2, "virtual_bytes")',fn)
        self.assertNotIn("kill(",fn)
        self.assertNotIn("purge(",fn)
        self.assertIn("if (f->jpeg) { CFRelease(f->jpeg); f->jpeg = NULL; }",src)
        self.assertIn("if (f->image) { CGImageRelease(f->image);",src)
        self.assertIn("if (f->rgba) { free(f->rgba); f->rgba = NULL; }",src)
        self.assertIn("if (f->gray) { free(f->gray); f->gray = NULL; }",src)

    def test_testlab_memory_gates_and_safe_disabled_mutations(self):
        lab=(ROOT/"lua/nktestlab.lua").read_text()
        self.assertIn('test("runtime","memory_telemetry"',lab)
        self.assertIn('test("vision","lazy_bitmap_memory"',lab)
        self.assertIn('test("vision","ocr_from_same_frame"',lab)
        self.assertIn('test("task","stop_is_not_called"',lab)
        self.assertIn('report.process_rss_available and "PASS" or "SKIP"',lab)

    @unittest.skipUnless(shutil.which("lua"), "Lua 5.4 runner unavailable")
    def test_optional_native_rss_report_and_full_gc(self):
        script=r'''
package.path="lua/?.lua;"..package.path
local samples=0
package.preload.nkvision_native=function()
  return {memoryStats=function()
    samples=samples+1
    return {rss_bytes=12582912 + samples*4096,
            virtual_bytes=33554432,scope="PROCESS"}
  end}
end
local mem=require("nkmemory")
local s=assert(mem.stats())
assert(s.scope=="LUA_HEAP_AND_OPTIONAL_PROCESS_RSS")
assert(s.process_rss_available and s.process_rss_bytes>12582912)
assert(s.process_virtual_bytes==33554432)
local part=assert(mem.release({mode="step",step_kb=128}))
assert(part.process_rss_available)
assert(part.process_rss_after>=part.process_rss_before)
assert(part.reclaimed_lua_kb>=0)
local whole=assert(mem.release({mode="full"}))
assert(whole.scope=="LUA_HEAP_AND_OPTIONAL_PROCESS_RSS")
assert(samples>=5)
local bad,err,code=mem.release({mode="kill-others"})
assert(bad==nil and code=="INVALID")
print("[NKLAB][MEMORY] PROCESS_RSS_MOCK_PASS")
'''
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"test.lua"
            path.write_text(script)
            r=subprocess.run(["lua",str(path)],cwd=ROOT,text=True,
                             capture_output=True,timeout=15)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("PROCESS_RSS_MOCK_PASS",r.stdout)

    def test_exit_crash_not_misreported_as_input_failure(self):
        src=(ROOT/"examples/test_lua_exit_probe_readonly.lua").read_text()
        self.assertIn('require,"nktouch_v7"',src)
        self.assertIn('[NKEXIT][DONE]',src)
        self.assertIn("Intentionally return",src)
        # Do not globally skip normal Lua finalizers just to hide a segfault.
        native_wrapper=(ROOT/"runtime/nktouch-lua").read_text()
        self.assertNotIn("os.exit(0, false)",native_wrapper)
        self.assertIn("exec",native_wrapper)

if __name__=="__main__":
    unittest.main()
