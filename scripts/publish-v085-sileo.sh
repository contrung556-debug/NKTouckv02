#!/usr/bin/env bash
# Publish ONLY the exact successful v0.8.5 Input Engine Pro rootless artifact; on-device testing pending.
# Preserve every prior NKTouch and NKCrane entry; fail closed on artifact collision.
set -euo pipefail
ARTIFACT_DIR="$(pwd)/sileo-artifact"
DEB_NAME="com.nk.nktouch_0.8.5_iphoneos-arm64.deb"
COUNT="$(find "$ARTIFACT_DIR" -type f -name '*.deb' | wc -l)"
[[ "$COUNT" -eq 1 ]] || { echo "Expected exactly one .deb, found $COUNT" >&2; exit 2; }
SOURCE="$(find "$ARTIFACT_DIR" -type f -name '*.deb' -print -quit)"
[[ "$(dpkg-deb -f "$SOURCE" Package)" == "com.nk.nktouch" ]]
[[ "$(dpkg-deb -f "$SOURCE" Version)" == "0.8.5" ]]
[[ "$(dpkg-deb -f "$SOURCE" Architecture)" == "iphoneos-arm64" ]]
[[ $(stat -c%s "$SOURCE") -gt 100000 ]]
sha256sum "$SOURCE"

# Inspect the actual package, not just source-level assertions.
TESTROOT="$(mktemp -d /tmp/nktouch-v085-package.XXXXXX)"
trap 'rm -rf "$TESTROOT"' EXIT
dpkg-deb -x "$SOURCE" "$TESTROOT"
LUA="$TESTROOT/var/jb/usr/share/nktouch/lua"
test -s "$TESTROOT/var/jb/usr/libexec/nktouch/lua54"
test -f "$LUA/nktouch.lua"
test -f "$LUA/nktestlab.lua"
grep -Fq 'function M.ocrWithFallback(' "$LUA/nktouch.lua"
grep -Fq 'frame_error_osstatus=status' "$LUA/nktouch.lua"
grep -Fq 'pixelbuffer_420f_probe' "$LUA/nktestlab.lua"
grep -Fq 'VERSION="0.8.5-beta"' "$LUA/nktestlab.lua"
test -s "$LUA/nkocr_perf.lua"
grep -Fq 'function M.benchmark(opts,deps)' "$LUA/nkocr_perf.lua"
grep -Fq 'function M.ocrIfStable(opts,deps)' "$LUA/nkocr_perf.lua"
test -s "$TESTROOT/var/jb/usr/share/nktouch/examples/test_ocr_perf_v085.lua"
test -s "$TESTROOT/var/jb/usr/share/nktouch/examples/test_ocr_stability_v085.lua"
test -x "$TESTROOT/var/jb/usr/bin/nktouchctl"
grep -Fq 'PACKAGE_VERSION="0.8.5"' "$TESTROOT/var/jb/usr/bin/nktouchctl"
test -s "$LUA/nkinput_v2.lua"
test -s "$LUA/nkinput_pro.lua"
grep -Fq 'function M.fast(nk,s,opts)' "$LUA/nkinput_pro.lua"
grep -Fq 'function M.safe(nk,s,opts)' "$LUA/nkinput_pro.lua"
grep -Fq 'function M.keyboard(nk,s,opts)' "$LUA/nkinput_pro.lua"
grep -Fq 'DUPLICATE_BLOCKED' "$LUA/nkinput_pro.lua"
grep -Fq 'ONCE_KEY_REQUIRED' "$LUA/nkinput_pro.lua"
grep -Fq 'DISPATCH_UNCERTAIN' "$LUA/nkinput_pro.lua"
grep -Fq 'function M.inputFast(value,options)' "$LUA/nktouch.lua"
grep -Fq 'function M.inputSafe(value,options)' "$LUA/nktouch.lua"
grep -Fq 'function M.inputKeyboard(value,options)' "$LUA/nktouch.lua"
grep -Fq 'return M.inputTextV2(value,options)' "$LUA/nktouch.lua"
test -s "$TESTROOT/var/jb/usr/share/nktouch/examples/test_input_fast_v085.lua"
test -s "$TESTROOT/var/jb/usr/share/nktouch/examples/test_input_safe_v085.lua"
grep -Fq 'ENABLE_REAL_INPUT=false' "$TESTROOT/var/jb/usr/share/nktouch/examples/test_input_fast_v085.lua"
grep -Fq 'ENABLE_REAL_INPUT=false' "$TESTROOT/var/jb/usr/share/nktouch/examples/test_input_safe_v085.lua"
grep -Fq 'foreground_verified' "$LUA/nktestlab.lua" 2>/dev/null && echo "foreground marker in lab Lua" || true
PC_DYLIB="$(find "$TESTROOT" -type f -name 'pccontrol.dylib' -print -quit)"
test -s "$PC_DYLIB"
python3 - "$PC_DYLIB" "$TESTROOT" <<'PY'
from pathlib import Path
import sys
core=Path(sys.argv[1]).read_bytes()
assert any("NK_FRAME_OCR_LOOPBACK_ONLY".encode(codec) in core
           for codec in ("utf-8","utf-16le","utf-16be")), "missing loopback guard"
assert any("NK_FRAME_OCR_UNAVAILABLE".encode(codec) in core
           for codec in ("utf-8","utf-16le","utf-16be")), "missing same-frame IPC marker"
root=Path(sys.argv[2])
app_markers=[
  p for p in root.rglob("*")
  if p.is_file() and p.stat().st_size > 300000 and p.stat().st_size < 50000000
]
assert any(any("foreground_verified".encode(codec) in p.read_bytes()
               for codec in ("utf-8","utf-16le","utf-16be"))
           for p in app_markers), "app does not contain foreground verification marker"
print("PASS: packaged loopback OCR IPC, live fallback and foreground verification")
PY

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git fetch origin sileo-repo
TARGET="/tmp/nk-sileo-v085"
rm -rf "$TARGET"
git worktree add --detach "$TARGET" FETCH_HEAD

for attempt in 1 2 3; do
  git -C "$TARGET" fetch origin sileo-repo
  git -C "$TARGET" reset --hard FETCH_HEAD
  # Never silently overwrite an already-published version with a different
  # artifact. Use a new version number for follow-up fixes.
  if [[ -f "$TARGET/debs/$DEB_NAME" ]] &&
     grep -Fq "Filename: debs/$DEB_NAME" "$TARGET/Packages" &&
     grep -Fq "Version: 0.8.5" "$TARGET/Packages" &&
     grep -Fq "Current package: com.nk.nktouch 0.8.5" "$TARGET/README.md"; then
    cmp -s "$SOURCE" "$TARGET/debs/$DEB_NAME" || { echo 'Existing v0.8.5 binary differs; refuse overwrite' >&2; exit 3; }
    echo 'NKTouch 0.8.5 is already published with matching binary'
    exit 0
  fi
  mkdir -p "$TARGET/debs"
  if [[ -f "$TARGET/debs/$DEB_NAME" ]] && ! cmp -s "$SOURCE" "$TARGET/debs/$DEB_NAME"; then
    echo 'Collision: v0.8.5 artifact differs from already published version' >&2
    exit 3
  fi
  cp "$SOURCE" "$TARGET/debs/$DEB_NAME"

  python3 - "$TARGET" "$DEB_NAME" <<'PY'
from pathlib import Path
import hashlib, re, subprocess, sys
root = Path(sys.argv[1])
filename = sys.argv[2]
deb = root/'debs'/filename
control = subprocess.check_output(['dpkg-deb','-f',str(deb)], text=True).rstrip()
metadata={}
for line in control.splitlines():
    if line and not line[0].isspace() and ':' in line:
        key,val=line.split(':',1)
        metadata[key]=val.strip()
assert metadata['Package']=='com.nk.nktouch'
assert metadata['Version']=='0.8.5'
assert metadata['Architecture']=='iphoneos-arm64'
data=deb.read_bytes()
entry='\n'.join([
    control,
    'Filename: debs/'+filename,
    'Size: '+str(len(data)),
    'MD5sum: '+hashlib.md5(data).hexdigest(),
    'SHA1: '+hashlib.sha1(data).hexdigest(),
    'SHA256: '+hashlib.sha256(data).hexdigest(),
    'Homepage: https://github.com/contrung556-debug/NKTouckv02',
])
pkg=root/'Packages'
old=pkg.read_text() if pkg.exists() else ''
keep=[]
for stanza in re.split(r'\n\s*\n', old.strip()) if old.strip() else []:
    lines={}
    for line in stanza.splitlines():
        if line and not line[0].isspace() and ':' in line:
            key,val=line.split(':',1)
            lines[key]=val.strip()
    if lines.get('Package')=='com.nk.nktouch' and lines.get('Version')=='0.8.5':
        continue
    keep.append(stanza.strip())
pkg.write_text('\n\n'.join([entry]+keep)+'\n')
assert old.count('Package: com.nktouch.nkcrane') <= pkg.read_text().count('Package: com.nktouch.nkcrane')
assert sum(1 for stanza in pkg.read_text().split('\n\n')
           if 'Version: 0.8.5\n' in stanza+'\n' and
           'Package: com.nk.nktouch\n' in stanza+'\n') == 1
readme=root/'README.md'
if readme.exists():
    text=readme.read_text()
    new=re.sub(r'(?m)^Current package: com\.nk\.nktouch .*$',
               'Current package: com.nk.nktouch 0.8.5 (iphoneos-arm64) — Input Engine Pro Native Fast/Safe/Keyboard with retained same-frame OCR (beta)',text)
    readme.write_text(new)
index=root/'index.html'
if index.exists():
    html=index.read_text()
    index.write_text(re.sub(r'NKTouch 0\.(?:7|8)\.\d+(?:\.\d+)*','NKTouch 0.8.5',html))
print('Preserved',len(keep),'existing package stanzas')
PY
  python3 - "$TARGET" <<'PY'
from pathlib import Path
import re,sys
root=Path(sys.argv[1])
stanzas=[s for s in re.split(r'\n\s*\n',(root/'Packages').read_text().strip()) if s.strip()]
def field(stanza,name):
    for line in stanza.splitlines():
        if line.startswith(name+': '): return line.split(': ',1)[1]
    return ''
for version in ('0.8.5','0.8.3','0.8.2'):
    assert sum(1 for stanza in stanzas if field(stanza,'Package')=='com.nk.nktouch'
               and field(stanza,'Version')==version)==1, f'missing/duplicate NKTouch {version}'
assert (root/'debs/com.nk.nktouch_0.8.3_iphoneos-arm64.deb').stat().st_size>100000
assert any('nkcrane' in field(s,'Package').lower() for s in stanzas), 'NKCrane missing'
print('PASS: 0.8.5 + 0.8.3 + 0.8.2 + NKCrane retained')
PY
  test -s "$TARGET/debs/com.nk.nktouch_0.8.3_iphoneos-arm64.deb"
  gzip -n -9 -c "$TARGET/Packages" > "$TARGET/Packages.gz"
  python3 - "$TARGET" <<'PY'
from pathlib import Path
from datetime import datetime, timezone
import hashlib,sys
root=Path(sys.argv[1])
release=root/'Release'
existing=release.read_text() if release.exists() else ''
header=existing.split('MD5Sum:',1)[0].strip()
lines=[x for x in header.splitlines() if not x.startswith('Date:')]
if not lines:
    lines=['Origin: NKTouch Repository','Label: NKTouch Repository',
           'Suite: stable','Codename: nktouch','Architectures: iphoneos-arm64',
           'Components: main']
lines.append('Date: '+datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000'))
checks=[]
for name in ('Packages','Packages.gz'):
    data=(root/name).read_bytes()
    checks.append((name,len(data),hashlib.md5(data).hexdigest(),hashlib.sha256(data).hexdigest()))
out='\n'.join(lines)+'\nMD5Sum:\n'
out+=''.join(f' {md5} {size} {name}\n' for name,size,md5,sha in checks)
out+='SHA256:\n'
out+=''.join(f' {sha} {size} {name}\n' for name,size,md5,sha in checks)
release.write_text(out)
PY

  (cd "$TARGET" && gzip -dc Packages.gz | cmp -s - Packages)
  grep -Fq "Filename: debs/$DEB_NAME" "$TARGET/Packages"
  git -C "$TARGET" add Packages Packages.gz Release README.md index.html "debs/$DEB_NAME"
  if git -C "$TARGET" diff --cached --quiet; then
    echo 'Sileo already has NKTouch 0.8.5'
    exit 0
  fi
  git -C "$TARGET" commit -m 'Publish NKTouch 0.8.5 Input Engine Pro beta to Sileo'
  if git -C "$TARGET" push origin HEAD:refs/heads/sileo-repo; then
    echo 'PUBLISHED NKTouch 0.8.5 to existing Sileo source (v0.8.3 and v0.8.2 retained)'
    git -C "$TARGET" rev-parse HEAD
    exit 0
  fi
  echo "Sileo branch advanced concurrently; retry $attempt/3" >&2
  sleep 2
done
echo 'FAILED to publish after 3 attempts' >&2
exit 1
