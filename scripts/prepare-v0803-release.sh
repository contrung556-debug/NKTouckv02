#!/usr/bin/env bash
# NKTouch v0.8.3 combines successful v0.8.2 OCR IPC candidate with
# external-app read-only Test Lab. Source staging only; no Sileo publishing.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0803-release.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0802-release.sh" "$SRC"

LIB="$SRC/layout/usr/share/nktouch/lua"
CTL="$SRC/layout/usr/bin/nktouchctl"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
CONTROL="$SRC/control"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"

# Do not mutate historical Lua APIs; overlay the consolidated test lab only.
install -m 0644 "$ROOT/lua/nktestlab.lua" "$LIB/nktestlab.lua"
python3 - "$CONTROL" "$VERSION" "$CTL" "$UI" "$LIB/nktestlab.lua" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui,lab=map(Path,sys.argv[1:])
def strict(path,old,new):
    s=path.read_text()
    if s.count(old)!=1:
        raise SystemExit(f"{path}: expected one {old!r}, got {s.count(old)}")
    path.write_text(s.replace(old,new,1))

strict(control,"Version: 0.8.2","Version: 0.8.3")
strict(control,
    "Description: NKTouch v0.8.2 same-JPEG OCR IPC beta: immutable frame sent to existing SpringBoard Vision service; device validation pending",
    "Description: NKTouch v0.8.3 External App Test beta: 5-core read-only Test Lab via managed Lua task, foreground guards and same-frame OCR IPC; device validation pending")
strict(ctl,'PACKAGE_VERSION="0.8.2"','PACKAGE_VERSION="0.8.3"')
strict(version,"NKTouch 0.8.2 Same-Frame OCR IPC Beta",
              "NKTouch 0.8.3 External App Test and OCR IPC Beta")
with version.open("a") as out:
    out.write("""
v0.8.3 experimental: adds an External App Test button in Test Lab with
installed-app picker. The existing nktask supervisor starts first, opens the
selected app, waits five seconds, then runs OCR/Color/Touch/Input/Memory
read-only checks. Foreign-app foreground must match before and after each
group; report includes target bundle, observed foreground and real OCR
backend, not OCR text. No auto-touch or text injection.
The v0.8.2 in-memory JPEG ROI OCR bridge is retained.
Device correctness, task switching and SpringBoard stability are UNVERIFIED.
""")
u=ui.read_text().replace("NKTouch 0.8.2","NKTouch 0.8.3")
u=u.replace('nkLabel:@"0.8.2"','nkLabel:@"0.8.3"')
u=u.replace('text:@"0.8.2"','text:@"0.8.3"')
u=u.replace("-- NKTouch Test Lab v0.8.2-beta",
            "-- NKTouch Test Lab v0.8.3-beta")
ui.write_text(u)
strict(lab,"-- NKTouch Test Lab v0.7.16-dev",
           "-- NKTouch Test Lab v0.8.3-beta")
strict(lab,'local M={VERSION="0.7.16-dev"}',
           'local M={VERSION="0.8.3-beta"}')
PY

python3 "$ROOT/scripts/apply-v0803-external-test.py" "$SRC"
grep -Fxq 'Version: 0.8.3' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.3"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.3-beta' "$LIB/nktestlab.lua"
grep -Fq 'external_read_only' "$LIB/nktestlab.lua"
grep -Fq 'labChooseExternalApp' "$UI"
grep -Fq 'labStartExternalRunner' "$UI"
grep -Fq 'NKLuaRun(@[@"target-run",path]' "$UI"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.8.3 External App Test staged (artifact only; iPhone tests required)'
