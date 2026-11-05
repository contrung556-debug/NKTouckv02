"""Check every published API entry against Lua/native implementation.

This is a SOURCE COVERAGE audit, not a claim of device-side correctness.
Build and publish are intentionally prohibited from this test.
"""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[1]
CATALOG=ROOT/"runtime/nktouch-api.tsv"
LIB=(ROOT/"lua/nktouch.lua").read_text()
NET=(ROOT/"lua/nknet.lua").read_text()
JSON=(ROOT/"lua/nkjson.lua").read_text()
VISION=(ROOT/"runtime/nkvision.m").read_text()
NATIVE=(ROOT/"runtime/nkcore.c").read_text()
FIX=(ROOT/"scripts/apply-v0712-inputtext-fix.py").read_text()
GUARD=(ROOT/"lua/nkcommand_contract.lua").read_text()

def catalog():
    out=[]
    for i,line in enumerate(CATALOG.read_text().splitlines(),1):
        if not line or line.lstrip().startswith("#"):
            continue
        fields=line.split("|",4)
        if len(fields)!=5:
            raise AssertionError(f"invalid API TSV at line {i}: {line[:120]}")
        out.append(dict(zip(("name","signature","category","description","example"),fields)))
    return out

def lua_has(src,method):
    key=re.escape(method)
    return bool(re.search(r"\bfunction\s+M\."+key+r"\s*\(",src)
         or re.search(r"\bM\."+key+r"\s*=",src))

class AllExistingCommandsAudit(unittest.TestCase):
    def test_unique_catalog_entries_and_categories(self):
        rows=catalog()
        self.assertGreaterEqual(len(rows),60)
        names=[x["name"] for x in rows]
        self.assertEqual(len(names),len(set(names)),"duplicate Lua API")
        self.assertTrue(all(x["signature"] and x["category"] for x in rows))
        required={"touch","timing","app","keyboard","vision","device","recorder",
                  "overlay","diagnostic","network","json"}
        cats={x["category"] for x in rows}
        self.assertTrue(required.issubset(cats),required-cats)
        print(f"[NKCMD][CATALOG] entries={len(rows)} categories={len(cats)}")

    def test_every_catalog_name_has_source_implementation(self):
        missing=[]
        for entry in catalog():
            name=entry["name"]
            parts=name.split(".")
            if parts[0]=="frame":
                ok=len(parts)==2 and bool(re.search(
                    r'\{"'+re.escape(parts[1])+r'",\s*nv_',VISION))
            elif len(parts)==3 and parts[0]=="nk" and parts[1]=="http":
                ok=lua_has(NET,parts[2])
            elif len(parts)==3 and parts[0]=="nk" and parts[1]=="json":
                ok=lua_has(JSON,parts[2])
            elif len(parts)==2 and parts[0]=="nk":
                ok=lua_has(LIB,parts[1])
            else:
                ok=False
            if not ok: missing.append(name)
        self.assertEqual(missing,[],f"catalog lists APIs not implemented: {missing}")

    def test_native_bridge_supports_critical_mutations(self):
        for name in ("tap","hold","swipe","path","openApp","sleep","inputTextV2",
                     "keyboard","cursor","delete","paste","getClipboard",
                     "setClipboard","getColor","findColor","findImage","ocr",
                     "screenshot","screen","foreground","toast"):
            self.assertRegex(NATIVE,r'\{"'+re.escape(name)+r'",\s*l_')
        self.assertIn("return M.inputTextV2(value,options)",FIX,
                      "the released script must use safe v2 default")
        self.assertIn('require("nkcommand_contract").install(M)',
                      (ROOT/"scripts/apply-v0716-command-contract.py").read_text())

    def test_guards_cover_main_dispatch_paths(self):
        for name in ("tap","hold","swipe","sleep","openApp","waitApp",
                     "moveCursor","delete","getColor","findColor","waitColor",
                     "tapColor","findImage","waitImage","tapImage","ocr",
                     "waitText","screenshot","status","toast"):
            self.assertIn('guard("'+name+'"',GUARD,
                          "missing argument validator for "+name)
        self.assertIn("side effect",GUARD)
        self.assertIn('return nil,"invalid "',GUARD)

    def test_development_branch_cannot_publish_or_build(self):
        # No release workflow or Sileo publisher should reference this DEV branch.
        branch="v0.7.16-command-hardening-dev"
        for p in (ROOT/".github/workflows").glob("*.yml"):
            data=p.read_text()
            if branch in data:
                self.assertNotIn("dpkg-deb --build",data)
                self.assertNotIn("publish-v0716",data)
                self.assertNotIn("runs-on: macos",data)
        self.assertNotIn("dpkg-deb",(ROOT/"scripts/stage-v0716-command-contract-dev.sh").read_text())
        self.assertNotIn("sileo-repo",(ROOT/"scripts/stage-v0716-command-contract-dev.sh").read_text())

if __name__=="__main__":
    unittest.main()
