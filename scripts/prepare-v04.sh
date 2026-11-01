#!/usr/bin/env bash
set -euo pipefail

SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUA_BIN="$ROOT/runtime/nktouch-lua"

if [[ ! -d "$SRC" ]]; then
  echo "Missing upstream source directory: $SRC" >&2
  exit 1
fi

if [[ ! -x "$LUA_BIN" ]]; then
  echo "Missing compiled Lua runtime: $LUA_BIN" >&2
  echo "Build runtime/nktouch-lua before running prepare-v04.sh" >&2
  exit 1
fi

# Reuse the proven v0.3 native packaging layer first.
bash "$ROOT/scripts/prepare-v03.sh" "$SRC"

# Upgrade package metadata to v0.4.
python3 - "$SRC/control" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace("Version: 0.3.0", "Version: 0.4.0")
s = s.replace(
    "Description: NKTouch v0.3 native-first rootless automation framework (GPL ZXTouch core)",
    "Description: NKTouch v0.4 native automation with bundled standalone Lua runtime (GPL ZXTouch core)",
)
p.write_text(s)
PY

SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if [[ -f "$SETTINGS" ]]; then
  python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace('NKTouch 0.3', 'NKTouch 0.4')
s = s.replace('ZXTouch GPL core • NKTouch native layer', 'ZXTouch GPL core • NKTouch native + Lua layer')
p.write_text(s)
PY
fi

mkdir -p \
  "$SRC/layout/usr/bin" \
  "$SRC/layout/usr/libexec/nktouch" \
  "$SRC/layout/usr/share/nktouch/lua" \
  "$SRC/layout/usr/share/doc/nktouch"

# Standalone Lua runtime and runner. No AutoTouch/Python/Lua package dependency
# is required for normal v0.4 script execution.
cp "$LUA_BIN" "$SRC/layout/usr/libexec/nktouch/lua"
cp "$ROOT/runtime/nktouch-run" "$SRC/layout/usr/bin/nktouch-run"
cp "$ROOT/lua/nktouch.lua" "$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
cp "$ROOT/lua/bootstrap.lua" "$SRC/layout/usr/share/nktouch/lua/bootstrap.lua"

if [[ -d "$ROOT/lua/examples" ]]; then
  mkdir -p "$SRC/layout/usr/share/nktouch/lua/examples"
  cp -R "$ROOT/lua/examples/." "$SRC/layout/usr/share/nktouch/lua/examples/"
fi

printf '%s\n' 'NKTouch 0.4.0' > "$SRC/layout/usr/share/doc/nktouch/VERSION"
chmod 755 \
  "$SRC/layout/usr/libexec/nktouch/lua" \
  "$SRC/layout/usr/bin/nktouch-run"

echo "--- NKTouch v0.4 package control ---"
cat "$SRC/control"
echo "--- NKTouch v0.4 runtimes ---"
file "$SRC/layout/usr/libexec/nktouch/nktouch-native"
file "$SRC/layout/usr/libexec/nktouch/lua"
echo "--- NKTouch v0.4 runner ---"
head -n 5 "$SRC/layout/usr/bin/nktouch-run"
