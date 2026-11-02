#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -f "$ROOT/scripts/prepare-v0741-video-ux.sh" ]] || { echo "Missing V7.4.1 preparation layer" >&2; exit 1; }
[[ -f "$ROOT/scripts/apply-v075-editor-runner-console.py" ]] || { echo "Missing V7.5 transformer" >&2; exit 1; }

# Keep every V7.4/V7.4.1 runtime and library behavior, then layer V7.5 on top.
bash "$ROOT/scripts/prepare-v0741-video-ux.sh" "$SRC"

SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
CONTROL="$SRC/control"
VERSION_DOC="$SRC/layout/usr/share/doc/nktouch/VERSION"
[[ -f "$SETTINGS" ]] || { echo "Missing SettingsPageViewController.m" >&2; exit 1; }
[[ -f "$CONTROL" ]] || { echo "Missing control file" >&2; exit 1; }

python3 "$ROOT/scripts/apply-v075-editor-runner-console.py" "$SETTINGS"

python3 - "$CONTROL" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
s=p.read_text()
s,n=re.subn(r'^Version:\s*[^\n]+$', 'Version: 0.7.5', s, count=1, flags=re.M)
if n!=1:
    raise SystemExit('Unable to update package Version to 0.7.5')
p.write_text(s)
PY

mkdir -p "$(dirname "$VERSION_DOC")"
cat > "$VERSION_DOC" <<'EOF'
NKTouch 0.7.5 Editor + Runner + Console

Core retained from V7.4/V7.4.1:
- Lua 5.4.9 runtime and luac54 syntax checker
- nktask task supervisor
- HTTP/JSON, recorder and task bundle APIs

V7.5 editor/runtime UX:
- Lua line-number gutter
- automatic indentation on newline
- Find / Replace / Undo / Redo menu
- realtime task log refresh
- elapsed task timer
- Restart task action
- Copy logs / Clear console
- INFO/WARN/ERROR-oriented console coloring
- runtime error line detection while preserving syntax-check jump behavior
EOF

# Contract guards: fail CI before Xcode if the V7.5 layer did not land.
grep -Fq '// NKTouch V7.5 Editor + Runner + Console' "$SETTINGS"
grep -Fq 'NK75LineNumberView' "$SETTINGS"
grep -Fq 'nk75_refreshRuntime' "$SETTINGS"
grep -Fq 'Restart tác vụ' "$SETTINGS"
grep -Fq 'Copy logs' "$SETTINGS"
grep -Fq 'Clear console' "$SETTINGS"
grep -Fq 'Tìm trong Lua' "$SETTINGS"
grep -Fq 'Thay tất cả' "$SETTINGS"
grep -q '^Version: 0.7.5$' "$CONTROL"
grep -Fq 'NKTouch 0.7.5 Editor + Runner + Console' "$VERSION_DOC"

echo "NKTouch V7.5 Editor + Runner + Console prepared"
