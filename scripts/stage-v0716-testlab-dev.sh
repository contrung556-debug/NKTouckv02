#!/usr/bin/env bash
# NKTouch v0.7.16 DEVELOPMENT STAGING ONLY.
# Produces staged Lua/UI source for tests, never compiles or publishes a deb.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v0716-testlab-dev.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/stage-v0716-command-contract-dev.sh" "$SRC"
LIB="$SRC/layout/usr/share/nktouch/lua"
install -m 0644 "$ROOT/lua/nktestlab.lua" "$LIB/nktestlab.lua"
python3 "$ROOT/scripts/apply-v0716-testlab-ui.py" "$SRC"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
grep -Fq 'NKLuaTestLabViewController' "$UI"
grep -Fq 'nkOpenTestLab' "$UI"
grep -Fq 'testlab-last.json' "$UI"
grep -Fq 'require("nkcommand_contract").install(M)' "$LIB/nktouch.lua"
grep -Fq 'NKTouch Test Lab v0.7.16-dev' "$LIB/nktestlab.lua"
test -s "$LIB/nktestlab.lua"
test -s "$LIB/nkcommand_contract.lua"
echo 'NKTouch Test Lab DEV staged: no build, no .deb, no Sileo publishing'
