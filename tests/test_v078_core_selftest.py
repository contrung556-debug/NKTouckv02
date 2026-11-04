from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TEST = ROOT / "lua/nkcore_selftest.lua"


class CoreSelfTestContract(unittest.TestCase):
    def test_readonly_default_and_no_uncontrolled_touch(self):
        s=TEST.read_text()
        for marker in (
            'local opts = {touch=false', 'if opts.touch then',
            'nk.tap(opts.x,opts.y)', 'read-only default', 'no blind swipe',
            'no blind hold', '[NKCORE][SUMMARY]',
            '"getColor"', '"findColor"', '"waitColorMatch"',
            '"screenshot"', '"screen"', '"orientation"', '"scale"',
            '"foreground"', '"sleep"', '"ping"',
            'os.remove(shot)', 'NKTOUCH_TASK_ID', 'os.exit(1)'
        ):
            self.assertIn(marker, s)
        self.assertNotIn('nk.swipe(',s)
        self.assertNotIn('nk.hold(',s)
        self.assertNotIn('nk.openApp(',s)

    def test_cli_and_app_integration_in_source(self):
        prepare=(ROOT/"scripts/prepare-v078-core-selftest.sh").read_text()
        patch=(ROOT/"scripts/apply-v078-core-selftest-ui.py").read_text()
        self.assertIn("prepare-v077-lua-core-reliability.sh",prepare)
        self.assertIn("install -m 0644",prepare)
        self.assertIn('core-selftest)',prepare)
        self.assertIn('exec "$TASK" start "$SELFTEST" --timeout 60 -- "$@"',prepare)
        self.assertIn("Version: 0.7.8",prepare)
        self.assertIn("NKTouch 0.7.8 Lua Core Self-Test",prepare)
        self.assertIn("[NKCORE][SUMMARY] status=PASS",patch)
        self.assertIn("stringWithContentsOfFile:",patch)
        self.assertIn("for(int i=0;i<120;i++",patch)
        self.assertIn("Core Self-Test",patch)
        # The original home Self Test is reused, not bypassed by a second task.
        self.assertIn("runSelfTest",patch)
        self.assertIn("Recorder",prepare)
        self.assertIn("test ! -e",prepare)

    @unittest.skipUnless(shutil.which("lua"), "host Lua needed for execution")
    def test_executable_core_selftest_success_failure_and_touch_consent(self):
        code = r'''
local path, mode = arg[1], arg[2]
arg = {}
local time = 0
local calls = 0
local touch = 0
local nk = {DIRECT=true}
package.loaded["nkcore"] = { nowMs=function() return time end }
nk.ping=function()
   if mode=="ping-fails" then return nil,"connection refused","CONNECT" end
   return true
end
nk.screen=function() return "1170.000000;;2532.000000" end
nk.orientation=function() return "1" end
nk.scale=function() return "3.0000" end
nk.foreground=function() return "com.apple.springboard" end
nk.sleep=function(ms) time=time+ms; return true end
nk.getColor=function(x,y)
  calls=calls+1
  assert(x==585 and y==1266)
  return {red=255,green=80,blue=40}
end
nk.matchColor=function() return true,{red=255,green=80,blue=40} end
nk.findColor=function(x,y,w,h,r1,r2,g1,g2,b1,b2,skip)
  assert(x==585 and y==1266 and w==1 and h==1 and skip==0)
  return {x=x,y=y,red=255,green=80,blue=40}
end
nk.waitColorMatch=function(r,g,b,t,region,timeout,interval)
  assert(region.w==1 and region.h==1 and timeout==0 and interval==100)
  return {x=region.x,y=region.y}
end
nk.screenshot=function(path)
  if mode=="screenshot-fails" then return nil,"cannot capture screenshot","IO" end
  return path
end
local originalOpen = io.open
io.open = function(p,m)
  if p:find("core%-selftest%-") then
    return {seek=function() return 1280 end,close=function() end}
  end
  return originalOpen(p,m)
end
os.remove = function() return true end
nk.tap = function(x,y)
  touch=touch+1
  assert(x==200 and y==300)
  return true
end
package.loaded["nktouch_v7"]=nk
if mode=="touch" then arg={"--touch","200","300"} end
dofile(path)
assert(calls>=1)
if mode=="touch" then assert(touch==1) else assert(touch==0) end
'''
        with tempfile.TemporaryDirectory() as d:
            script=Path(d)/"test.lua"
            script.write_text(code)
            for scenario in ("pass","ping-fails","screenshot-fails","touch"):
                with self.subTest(scenario=scenario):
                    run=subprocess.run(["lua",str(script),str(TEST),scenario],
                                       text=True,capture_output=True,timeout=15)
                    output=run.stdout+run.stderr
                    expect_failure=scenario in ("ping-fails","screenshot-fails")
                    self.assertEqual(run.returncode!=0,expect_failure,output)
                    self.assertIn("[NKCORE][SUMMARY] status="+
                                  ("FAIL" if expect_failure else "PASS"), output)
                    self.assertIn("[NKCORE][PASS] getColor",output)
                    if scenario=="touch":
                        self.assertIn("[NKCORE][WARN] tap",output)
                    else:
                        self.assertIn("[NKCORE][SKIP] tap",output)
                    if scenario=="ping-fails":
                        self.assertIn("[NKCORE][FAIL] ping",output)


if __name__=="__main__":
    unittest.main()
