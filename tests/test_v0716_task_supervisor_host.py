"""NKTask process supervisor host integration tests.

Compiles an ISOLATED Linux copy with all runtime paths rewritten to a temporary
directory and /usr/bin/lua. Never starts/modifies iPhone/system services.
"""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]
C=ROOT/"runtime/nktask.c"

class NKTaskSupervisorHost(unittest.TestCase):
    @unittest.skipUnless(shutil.which("gcc") and shutil.which("lua") and
                         shutil.which("luac"),"Host GCC and Lua required")
    def test_lua_start_success_stop_and_timeout(self):
        with tempfile.TemporaryDirectory(prefix="nktouch-supervisor-") as tmp:
            root=Path(tmp)
            base=root/"NKTouch"
            program=root/"nktask-host"
            source=C.read_text()
            mapping={
                r'#define BASE "/var/mobile/Library/NKTouch"':
                   '#define BASE "'+str(base)+'"',
                r'#define LUA "/var/jb/usr/bin/nktouch-lua"':
                   '#define LUA "'+shutil.which("lua")+'"',
                r'#define LUAC "/var/jb/usr/libexec/nktouch/luac54"':
                   '#define LUAC "'+shutil.which("luac")+'"',
                r'#define ENGINE "/var/jb/usr/bin/nktask"':
                   '#define ENGINE "'+str(program)+'"',
            }
            for old,new in mapping.items():
                self.assertEqual(source.count(old),1,"base macro changed "+old)
                source=source.replace(old,new,1)
            test_src=root/"host_nktask.c";test_src.write_text(source)
            cc=subprocess.run(["gcc","-std=c11","-O2","-Wall","-Wextra",
                         str(test_src),"-o",str(program)],
                         capture_output=True,text=True,timeout=25)
            self.assertEqual(cc.returncode,0,cc.stdout+cc.stderr)
            def call(*args,timeout=8):
                return subprocess.run([str(program),*map(str,args)],
                   capture_output=True,text=True,timeout=timeout)
            def wait_state(task_id,expected,seconds=5):
                deadline=time.monotonic()+seconds
                last=""
                while time.monotonic()<deadline:
                    r=call("status",task_id,timeout=2)
                    if r.returncode==0:
                        data=dict(x.split("=",1) for x in r.stdout.splitlines()
                                  if "=" in x)
                        last=data.get("state","")
                        if last==expected:return data
                    time.sleep(0.08)
                self.fail(f"NKTask expected {expected}; final={last}")
            def start(path,*args):
                r=call("start",path,*args)
                self.assertEqual(r.returncode,0,r.stdout+r.stderr)
                m=re.search(r"^task_id=([A-Za-z0-9_-]+)$",r.stdout,re.M)
                self.assertIsNotNone(m,r.stdout)
                return m.group(1)
            done=root/"complete.lua"
            done.write_text('print("TASK_OK")\n')
            id1=start(done)
            result=wait_state(id1,"success")
            self.assertEqual(result["exit_code"],"0")
            logs=call("logs",id1,"20")
            self.assertEqual(logs.returncode,0,logs.stderr)
            self.assertIn("TASK_OK",logs.stdout)
            self.assertEqual(call("status").stdout.strip(),"state=idle")

            loop=root/"loop.lua"
            loop.write_text('while true do local x=1 end\n')
            id2=start(loop)
            try:
                wait_state(id2,"running")
                stop=call("stop",id2)
                self.assertEqual(stop.returncode,0,stop.stdout+stop.stderr)
                result=wait_state(id2,"stopped")
                self.assertEqual(result["state"],"stopped")
                self.assertEqual(call("status").stdout.strip(),"state=idle")
            finally:
                # Do not leave a runaway child if the assertions fail.
                call("stop",id2,timeout=3)

            id3=start(loop,"--timeout","1")
            try:
                wait_state(id3,"running")
                result=wait_state(id3,"timeout",seconds=6)
                self.assertEqual(result["state"],"timeout")
                self.assertEqual(result["exit_code"],"124")
                self.assertEqual(call("status").stdout.strip(),"state=idle")
            finally:
                call("stop",id3,timeout=3)
            print("[NKQA][TASK_SUPERVISOR] PASS success/stopped/timeout/idle")

if __name__=="__main__":
    unittest.main()
