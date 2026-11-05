#!/usr/bin/env bash
# DEV ONLY: stage command contracts without generating .deb or publishing Sileo.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v0716-command-contract-dev.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0715-lua-selftest.sh" "$SRC"
LIB="$SRC/layout/usr/share/nktouch/lua"
install -m 0644 "$ROOT/lua/nkcommand_contract.lua" "$LIB/nkcommand_contract.lua"
python3 "$ROOT/scripts/apply-v0716-command-contract.py" "$SRC"
grep -Fq 'require("nkcommand_contract").install(M)' "$LIB/nktouch.lua"
grep -Fq 'function M.inputText(value,options)' "$LIB/nktouch.lua"
test -s "$LIB/nkcommand_contract.lua"
echo 'NKTouch 0.7.16 DEV staged for contract tests only. Build not requested.'
