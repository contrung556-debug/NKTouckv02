#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -f "$ROOT/patches/NKLuaWorkspace.m.inc" ]] || { echo "Missing Lua Workspace UX patch" >&2; exit 1; }
[[ -f "$ROOT/scripts/apply-v741-video-ux.py" ]] || { echo "Missing V7.4.1 video UX transformer" >&2; exit 1; }

python3 "$ROOT/scripts/apply-v741-video-ux.py" "$ROOT/patches/NKLuaWorkspace.m.inc"

# Fix Logs argument handling after the V7.4.1 transformer has run.
# nktask syntax is: logs [TASK_ID] [LINES]. Therefore a line limit may only
# be appended when a task ID is present; otherwise `logs 100` treats 100 as ID.
python3 - "$ROOT/patches/NKLuaWorkspace.m.inc" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
old = '- (void)logsTapped{__weak typeof(self)w=self;NSMutableArray*args=[NSMutableArray arrayWithObject:@"logs"];if(self.taskID.length)[args addObject:self.taskID];[args addObject:@"100"];[self command:args state:@"Đang tải logs…" done:^(int c,NSString *o){w.console.text=o;if(c!=0){w.runState.text=@"Log chưa sẵn sàng";w.runState.textColor=NKMuted();}else [w pollTaskStatus];}];}'
new = '- (void)logsTapped{__weak typeof(self)w=self;NSMutableArray*args=[NSMutableArray arrayWithObject:@"logs"];if(self.taskID.length){[args addObject:self.taskID];[args addObject:@"100"];}[self command:args state:@"Đang tải logs…" done:^(int c,NSString *o){if(c!=0){w.console.text=@"[NKTouch] Chưa có tác vụ hoặc log để hiển thị.";w.runState.text=@"Log chưa sẵn sàng";w.runState.textColor=NKMuted();}else{w.console.text=o;[w pollTaskStatus];}}];}'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('Could not locate transformed v0.7.4.1 Logs handler')
p.write_text(s)
PY

# Regression guards: never emit the ambiguous `logs 100` argument layout.
grep -Fq 'if(self.taskID.length){[args addObject:self.taskID];[args addObject:@"100"];}' "$ROOT/patches/NKLuaWorkspace.m.inc"
if grep -Fq 'if(self.taskID.length)[args addObject:self.taskID];[args addObject:@"100"];' "$ROOT/patches/NKLuaWorkspace.m.inc"; then
    echo "Invalid Logs argument layout: line count can become task ID" >&2
    exit 1
fi

bash "$ROOT/scripts/prepare-v074.sh" "$SRC"

SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
[[ -f "$SETTINGS" ]] || { echo "Missing SettingsPageViewController.m" >&2; exit 1; }

python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
old='''    Class workspaceClass = NSClassFromString(@"NKLuaWorkspaceViewController");
    if (!workspaceClass) {
        [Util showAlertBoxWithOneOption:self title:@"Lua Workspace"
            message:@"Lua Workspace UI is unavailable in this build."
            buttonString:@"OK"];
        return;
    }
    UIViewController *workspaceController = [[workspaceClass alloc] init];
    [self.navigationController pushViewController:workspaceController animated:YES];'''
new='''    Class workspaceClass = NSClassFromString(@"NKLuaLibraryViewController");
    if (!workspaceClass) {
        [Util showAlertBoxWithOneOption:self title:@"Lua Workspace"
            message:@"Lua Workspace UI is unavailable in this build."
            buttonString:@"OK"];
        return;
    }
    UIViewController *workspaceController = [[workspaceClass alloc] init];
    workspaceController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:workspaceController animated:YES];'''
if old not in s:
    raise SystemExit('Unable to convert Settings entry to direct Lua Workspace library')
s=s.replace(old,new,1)
p.write_text(s)
PY

# CI compatibility for the final .deb collection step. The Theos package may
# live below packages/ and macOS runners do not always expose dpkg-deb on PATH.
# Install the compatibility tools only *after* packaging, so Theos itself keeps
# using its own packaging toolchain unchanged.
CI_BIN="$ROOT/.ci-v741-bin"
mkdir -p "$CI_BIN"

cat > "$CI_BIN/dpkg-deb" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# Prefer a real dpkg-deb when Homebrew/system provides one.
for real in /opt/homebrew/bin/dpkg-deb /usr/local/bin/dpkg-deb /usr/bin/dpkg-deb; do
    if [[ -x "$real" && "$real" != "$0" ]]; then
        exec "$real" "$@"
    fi
done

member_for() {
    local deb="$1" prefix="$2"
    ar t "$deb" | tr -d '\r' | awk -v p="$prefix" 'index($0,p".tar")==1 {print; exit}'
}

stream_member() {
    local deb="$1" member="$2"
    case "$member" in
        *.gz)  ar p "$deb" "$member" | gzip -dc ;;
        *.xz)  ar p "$deb" "$member" | xz -dc ;;
        *.zst) ar p "$deb" "$member" | zstd -qdc ;;
        *.bz2) ar p "$deb" "$member" | bzip2 -dc ;;
        *.lzma) ar p "$deb" "$member" | xz --format=lzma -dc ;;
        *)     ar p "$deb" "$member" ;;
    esac
}

read_control() {
    local deb="$1" member
    member="$(member_for "$deb" control)"
    [[ -n "$member" ]] || { echo "dpkg-deb shim: control archive missing" >&2; return 2; }
    stream_member "$deb" "$member" | tar -xOf - ./control 2>/dev/null || \
        stream_member "$deb" "$member" | tar -xOf - control
}

case "${1:-}" in
    -f|--field)
        deb="${2:?missing deb path}"
        field="${3:-}"
        control="$(read_control "$deb")"
        if [[ -z "$field" ]]; then
            printf '%s\n' "$control"
        else
            printf '%s\n' "$control" | awk -v f="$field" 'index($0,f ":")==1 {sub("^[^:]*:[[:space:]]*",""); print; exit}'
        fi
        ;;
    -I|--info)
        deb="${2:?missing deb path}"
        read_control "$deb"
        ;;
    -c|--contents)
        deb="${2:?missing deb path}"
        member="$(member_for "$deb" data)"
        [[ -n "$member" ]] || { echo "dpkg-deb shim: data archive missing" >&2; exit 2; }
        stream_member "$deb" "$member" | tar -tvf -
        ;;
    *)
        echo "dpkg-deb shim only supports -f, -I and -c (got: $*)" >&2
        exit 2
        ;;
esac
SH
chmod 755 "$CI_BIN/dpkg-deb"

cat > "$CI_BIN/nk-v741-post-package" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
PKG_DIR="${1:-packages}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

DEB="$(python3 - "$PKG_DIR" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
files = [p for p in root.rglob('*.deb') if p.name != 'nktouch-v741-latest.deb']
if not files:
    raise SystemExit(1)
print(max(files, key=lambda p: p.stat().st_mtime))
PY
)" || {
    echo "NKTouch post-package: no .deb found under $PKG_DIR" >&2
    exit 1
}

OUT="$PKG_DIR/nktouch-v741-latest.deb"
if [[ "$DEB" != "$OUT" ]]; then
    cp "$DEB" "$OUT"
fi
printf 'NKTouch post-package selected: %s\n' "$DEB"

# GitHub Actions applies GITHUB_PATH additions to subsequent steps.
if [[ -n "${GITHUB_PATH:-}" ]]; then
    printf '%s\n' "$SELF_DIR" >> "$GITHUB_PATH"
fi
SH
chmod 755 "$CI_BIN/nk-v741-post-package"

# The hook runs after Theos has finished producing the package. It normalizes
# the artifact into packages/ and exposes the read-only dpkg-deb shim for the
# following Inspect step without touching the package build itself.
POST_PACKAGE="$CI_BIN/nk-v741-post-package"
cat >> "$SRC/Makefile" <<MAKE

# NKTouch v0.7.4.1 CI artifact compatibility hook
after-package::
	@bash "$POST_PACKAGE" packages
MAKE

grep -q 'V7.4.1 video UX hotfix' "$SETTINGS"
grep -q 'NSClassFromString(@"NKLuaLibraryViewController")' "$SETTINGS"
grep -q 'workspaceController.hidesBottomBarWhenPushed = YES' "$SETTINGS"
grep -q 'Gần đây' "$SETTINGS"
grep -q 'trailingSwipeActionsConfigurationForRowAtIndexPath' "$SETTINGS"
grep -q 'OCR (chủ động)' "$SETTINGS"
grep -q 'startTaskPolling' "$SETTINGS"
grep -q 'Cú pháp hợp lệ' "$SETTINGS"
grep -q 'NKTouch v0.7.4.1 CI artifact compatibility hook' "$SRC/Makefile"

echo "NKTouch V7.4.1 video UX hotfix prepared"
