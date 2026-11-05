#!/usr/bin/env python3
"""Development-only integration of Lua command argument contracts.

Apply to STAGED v0.7.15 sources.  Do not alter historical release branches.
Do not produce a deb, bump the package version, or publish anything.
"""
from pathlib import Path
import sys

if len(sys.argv)!=2:
    raise SystemExit("usage: apply-v0716-command-contract.py <staged-upstream>")
srcroot=Path(sys.argv[1])
lua=srcroot/"layout/usr/share/nktouch/lua/nktouch.lua"
if not lua.is_file():
    raise SystemExit("staged nktouch.lua missing")
src=lua.read_text()
assert "function M.inputText(value,options)" in src, "v0.7.12 effective inputText fix missing"
assert "function M.captureFrame()" in src, "Vision Core missing"
assert "function M.waitColorMatch(" in src, "Color Core missing"
anchor="\nreturn M\n"
assert src.count(anchor)==1, "unexpected nktouch.lua return marker"
assert 'require("nkcommand_contract").install(M)' not in src
src=src.replace(anchor, '''
-- v0.7.16-dev: validate user API arguments before native/CLI dispatch.
-- Keep this late in module initialization so the AutoTouch global aliases
-- created by installAutoTouchCompat bind to the guarded functions.
require("nkcommand_contract").install(M)
''' + anchor,1)
lua.write_text(src)
print("NKTouch 0.7.16-dev Lua command argument contracts integrated; no build")
