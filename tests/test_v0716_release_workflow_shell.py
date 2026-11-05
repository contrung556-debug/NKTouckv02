"""Bash -n every multiline run block of the v0.7.16 macOS release workflow.

This catches broken quoting BEFORE expensive Xcode/Theos CI is triggered.
A source shell-syntax pass does not imply that the iOS build succeeds.
"""
from pathlib import Path
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]
YAML=ROOT/".github/workflows/build-v0716-reliability-testlab.yml"

def shell_blocks():
    lines=YAML.read_text().splitlines()
    blocks=[]
    for idx,line in enumerate(lines):
        if line.startswith("        run: |"):
            nested=[]
            for text in lines[idx+1:]:
                if text.strip() and not text.startswith("          "):
                    break
                nested.append(text[10:] if text.startswith("          ") else "")
            blocks.append((idx+1,"\n".join(nested)+"\n"))
    return blocks

class ReleaseWorkflowSyntax(unittest.TestCase):
    def test_every_multiline_shell_has_valid_bash_syntax(self):
        blocks=shell_blocks()
        self.assertGreaterEqual(len(blocks),10)
        for line,script in blocks:
            with self.subTest(line=line):
                result=subprocess.run(["bash","-n"],input=script,text=True,
                                      capture_output=True,timeout=8)
                self.assertEqual(result.returncode,0,
                    f"workflow run block at line {line}: {result.stderr}")
    def test_release_still_requires_user_marker_and_build_success(self):
        source=YAML.read_text()
        self.assertIn("release/v0716-build-ready.txt",source)
        self.assertEqual(source.count("\n  publish-sileo:\n"),1)
        self.assertIn("if: needs.build-rootless.result == 'success'",source)
        self.assertIn("scripts/prepare-v0716-release.sh upstream",source)
        self.assertIn("scripts/publish-v0716-sileo.sh",source)
        self.assertIn(
            "grep -Fxq 'NKTouch 0.7.16 Seven-Group Test Lab Beta' "
            "upstream/layout/usr/share/doc/nktouch/VERSION",source)

if __name__=="__main__":
    unittest.main()
