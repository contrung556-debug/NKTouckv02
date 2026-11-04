#!/usr/bin/env python3
"""Stage-time fix for NKTouch v0.7.12: make inputText use safe v2 transport.

Keep the historical nk.text / nk.legacyInputText explicit. Never retry text
automatically, and install AutoTouch-style globals for editor-run scripts.
Do not mutate the retained v0.7.10/11 source baseline.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: apply-v0712-inputtext-fix.py <staged-upstream>")
root = Path(sys.argv[1])
library = root / "layout/usr/share/nktouch/lua/nktouch.lua"
settings = root / "zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if not library.is_file() or not settings.is_file():
    raise SystemExit("missing staged input library or Target Apps editor")

src = library.read_text()
legacy_alias = "M.inputText=M.text"
assert src.count(legacy_alias) == 1, "unexpected v0.7.11 inputText alias"
src = src.replace(legacy_alias, "M.legacyInputText=M.text", 1)
anchor = "function M.inputPassword(value,options)\n"
assert src.count(anchor) == 1, "missing Input Engine v2 integration"
src = src.replace(anchor, """-- v0.7.12: regular inputText uses UTF-8-safe Input Engine v2 by default.
-- No legacy resend if delivery cannot be confirmed; nk.text is opt-in legacy.
function M.inputText(value,options)
  return M.inputTextV2(value,options)
end
""" + anchor, 1)
assert 'function M.inputText(value,options)' in src
assert 'M.legacyInputText=M.text' in src
assert '_G.inputText=M.inputText' in src
library.write_text(src)

ui = settings.read_text()
# Scripts launched from the editor already import nktouch in their bootstrap;
# install its compatibility globals there so unqualified inputText("..."),
# tap(...), sleep(...) also work without a separate require in user scripts.
needle = """      @"local nk=require('nktouch')\\n"
"""
assert ui.count(needle) == 1, "unexpected Target Apps bootstrap baseline"
replacement = needle + """      @"nk.installAutoTouchCompat()\\n"
"""
ui = ui.replace(needle, replacement, 1)
assert ui.index('nk.installAutoTouchCompat()') < ui.index('loadfile(%@')
settings.write_text(ui)
print("NKTouch 0.7.12 staged: inputText -> v2, editor globals installed")
