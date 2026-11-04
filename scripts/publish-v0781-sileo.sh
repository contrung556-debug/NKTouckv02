#!/usr/bin/env bash
# Publish only a green, inspected NKTouch 0.7.8.1 rootless artifact.
# Preserve all previous NKTouch and NKCrane package entries.
set -euo pipefail
ARTIFACT_DIR="$(pwd)/sileo-artifact"
DEB_NAME="com.nk.nktouch_0.7.8.1_iphoneos-arm64.deb"
COUNT="$(find "$ARTIFACT_DIR" -type f -name '*.deb' | wc -l)"
[[ "$COUNT" -eq 1 ]] || { echo "Expected exactly one .deb, found $COUNT" >&2; exit 2; }
SOURCE="$(find "$ARTIFACT_DIR" -type f -name '*.deb' -print -quit)"
[[ "$(dpkg-deb -f "$SOURCE" Package)" == "com.nk.nktouch" ]]
[[ "$(dpkg-deb -f "$SOURCE" Version)" == "0.7.8.1" ]]
[[ "$(dpkg-deb -f "$SOURCE" Architecture)" == "iphoneos-arm64" ]]
[[ $(stat -c%s "$SOURCE") -gt 100000 ]]
sha256sum "$SOURCE"

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git fetch origin sileo-repo
TARGET="/tmp/nk-sileo-v0781"
rm -rf "$TARGET"
git worktree add --detach "$TARGET" FETCH_HEAD

for attempt in 1 2 3; do
  git -C "$TARGET" fetch origin sileo-repo
  git -C "$TARGET" reset --hard FETCH_HEAD
  mkdir -p "$TARGET/debs"
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
assert metadata['Version']=='0.7.8.1'
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
    if lines.get('Package')=='com.nk.nktouch' and lines.get('Version')=='0.7.8.1':
        continue
    keep.append(stanza.strip())
pkg.write_text('\n\n'.join([entry]+keep)+'\n')
assert old.count('Package: com.nktouch.nkcrane') <= pkg.read_text().count('Package: com.nktouch.nkcrane')
assert sum(1 for stanza in pkg.read_text().split('\n\n')
           if 'Version: 0.7.8.1\n' in stanza+'\n' and
           'Package: com.nk.nktouch\n' in stanza+'\n') == 1
readme=root/'README.md'
if readme.exists():
    text=readme.read_text()
    new=re.sub(r'(?m)^Current package: com\.nk\.nktouch .*$',
               'Current package: com.nk.nktouch 0.7.8.1 (iphoneos-arm64) — Core Self-Test Hotfix',text)
    readme.write_text(new)
index=root/'index.html'
if index.exists():
    html=index.read_text()
    index.write_text(re.sub(r'NKTouch 0\.7\.\d+(?:\.\d+)*','NKTouch 0.7.8.1',html))
print('Preserved',len(keep),'existing package stanzas')
PY
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
    echo 'Sileo already has NKTouch 0.7.8.1'
    exit 0
  fi
  git -C "$TARGET" commit -m 'Publish NKTouch 0.7.8.1 Core Self-Test Hotfix to Sileo'
  if git -C "$TARGET" push origin HEAD:refs/heads/sileo-repo; then
    echo 'PUBLISHED NKTouch 0.7.8.1 to existing Sileo source'
    git -C "$TARGET" rev-parse HEAD
    exit 0
  fi
  echo "Sileo branch advanced concurrently; retry $attempt/3" >&2
  sleep 2
done
echo 'FAILED to publish after 3 attempts' >&2
exit 1
