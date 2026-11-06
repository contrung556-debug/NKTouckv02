#!/usr/bin/env bash
set -euo pipefail
trap 'rc=$?; echo "NKTouch v0.8.12 publish failed at line \${LINENO} (exit \${rc}): \${BASH_COMMAND}" >&2' ERR
ARTIFACT_DIR="$(pwd)/sileo-artifact"
DEB_NAME="com.nk.nktouch_0.8.12_iphoneos-arm64.deb"
mapfile -t DEBS < <(find "$ARTIFACT_DIR" -type f -name '*.deb' -print)
[[ "\${#DEBS[@]}" -eq 1 ]] || { echo "Expected one .deb, found \${#DEBS[@]}" >&2; exit 2; }
SOURCE="\${DEBS[0]}"
[[ "$(dpkg-deb -f "$SOURCE" Package)" == "com.nk.nktouch" ]]
[[ "$(dpkg-deb -f "$SOURCE" Version)" == "0.8.12" ]]
[[ "$(dpkg-deb -f "$SOURCE" Architecture)" == "iphoneos-arm64" ]]
[[ "$(stat -c%s "$SOURCE")" -gt 100000 ]]
sha256sum "$SOURCE"
TESTROOT="$(mktemp -d /tmp/nktouch-v0812-package.XXXXXX)"
TARGET="$(mktemp -d /tmp/nktouch-v0812-sileo.XXXXXX)"
trap 'rm -rf "$TESTROOT" "$TARGET"' EXIT
dpkg-deb -x "$SOURCE" "$TESTROOT"
test -x "$TESTROOT/var/jb/usr/bin/nktouchctl"
grep -Fq 'PACKAGE_VERSION="0.8.12"' "$TESTROOT/var/jb/usr/bin/nktouchctl"
test -s "$TESTROOT/var/jb/usr/share/nktouch/lua/nkvision_state.lua"
test -s "$TESTROOT/var/jb/usr/share/nktouch/lua/nkfocus_state.lua"
test -s "$TESTROOT/var/jb/usr/share/nktouch/examples/test_vision_state_v0811.lua"
test -s "$TESTROOT/var/jb/usr/share/nktouch/examples/test_focus_state_v0812.lua"
grep -Fq 'Read-only' "$TESTROOT/var/jb/usr/share/nktouch/lua/nkfocus_state.lua"
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git fetch origin sileo-repo
git worktree add --detach "$TARGET" FETCH_HEAD
for attempt in 1 2 3; do
  git -C "$TARGET" fetch origin sileo-repo
  git -C "$TARGET" reset --hard FETCH_HEAD
  EXISTING="$TARGET/debs/$DEB_NAME"
  if [[ -f "$EXISTING" ]]; then
    if cmp -s "$SOURCE" "$EXISTING" && grep -Fq "Filename: debs/$DEB_NAME" "$TARGET/Packages" && grep -Fq 'Version: 0.8.12' "$TARGET/Packages"; then
      echo 'NKTouch 0.8.12 already published with identical binary'
      exit 0
    fi
    echo 'Version collision: existing v0.8.12 differs; refusing overwrite' >&2
    exit 3
  fi
  cp "$SOURCE" "$EXISTING"
  python3 - "$TARGET" "$DEB_NAME" <<'PY'
from pathlib import Path
import hashlib, re, subprocess, sys
root=Path(sys.argv[1]); filename=sys.argv[2]; deb=root/'debs'/filename
control=subprocess.check_output(['dpkg-deb','-f',str(deb)],text=True).rstrip()
fields={}
for line in control.splitlines():
    if line and not line[0].isspace() and ':' in line:
        k,v=line.split(':',1); fields[k]=v.strip()
assert fields.get('Package')=='com.nk.nktouch'
assert fields.get('Version')=='0.8.12'
assert fields.get('Architecture')=='iphoneos-arm64'
data=deb.read_bytes()
stanza='\n'.join([control,'Filename: debs/'+filename,'Size: '+str(len(data)),
    'MD5sum: '+hashlib.md5(data).hexdigest(),
    'SHA1: '+hashlib.sha1(data).hexdigest(),
    'SHA256: '+hashlib.sha256(data).hexdigest(),
    'Homepage: https://github.com/contrung556-debug/NKTouckv02'])
pkg=root/'Packages'; old=pkg.read_text()
for version in ('0.8.10','0.8.9','0.8.8'):
    assert f'Version: {version}' in old, f'expected rollback {version} entry'
stanzas=[s.strip() for s in re.split(r'\n\s*\n',old.strip()) if s.strip()]
assert not any(re.search(r'(?m)^Version: 0\.8\.12$',s) for s in stanzas)
pkg.write_text(stanza+'\n\n'+'\n\n'.join(stanzas)+'\n')
readme=root/'README.md'; txt=readme.read_text()
pattern=r'(?m)^Current package: com\.nk\.nktouch .*$'
replacement='Current package: com.nk.nktouch 0.8.12 (iphoneos-arm64) — OCR State + Native Focus Reliability beta (device validation pending)'
assert re.search(pattern,txt), 'README current package line not found'
readme.write_text(re.sub(pattern,replacement,txt))
index=root/'index.html'; html=index.read_text()
assert 'NKTouch 0.8.10' in html
index.write_text(html.replace('NKTouch 0.8.10','NKTouch 0.8.12'))
PY
  gzip -n -9 -c "$TARGET/Packages" > "$TARGET/Packages.gz"
  python3 - "$TARGET" <<'PY'
from pathlib import Path
from datetime import datetime,timezone
import hashlib,sys
root=Path(sys.argv[1]); p=root/'Release'; old=p.read_text()
assert 'MD5Sum:' in old and 'SHA256:' in old
header=old.split('MD5Sum:',1)[0]
lines=[x for x in header.splitlines() if not x.startswith('Date:')]
lines.append('Date: '+datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000'))
out='\n'.join(lines)+'\nMD5Sum:\n'
for name in ('Packages','Packages.gz'):
 d=(root/name).read_bytes(); out+=f' {hashlib.md5(d).hexdigest()} {len(d)} {name}\n'
out+='SHA256:\n'
for name in ('Packages','Packages.gz'):
 d=(root/name).read_bytes(); out+=f' {hashlib.sha256(d).hexdigest()} {len(d)} {name}\n'
p.write_text(out)
PY
  (cd "$TARGET" && gzip -dc Packages.gz | cmp -s - Packages)
  for version in 0.8.12 0.8.10 0.8.9 0.8.8; do grep -Fxq "Version: $version" "$TARGET/Packages"; done
  git -C "$TARGET" add Packages Packages.gz Release README.md index.html "debs/$DEB_NAME"
  git -C "$TARGET" commit -m 'Publish NKTouch 0.8.12 OCR State and Focus Reliability beta to Sileo'
  if git -C "$TARGET" push origin HEAD:refs/heads/sileo-repo; then
    echo "PUBLISHED NKTouch 0.8.12; prior versions retained"
    git -C "$TARGET" rev-parse HEAD
    exit 0
  fi
  echo "Sileo source changed concurrently; retry $attempt/3" >&2
  sleep 2
done
echo 'Failed to publish after three attempts' >&2
exit 1
