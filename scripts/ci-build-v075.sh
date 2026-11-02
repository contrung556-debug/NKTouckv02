#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UPSTREAM_REPO="https://github.com/epic0001/zxtouchrootless.git"
UPSTREAM_SHA="a602da112ef1a688fb2601424443abb1ccc28c63"
LUA_VERSION="5.4.9"
LUA_SHA256="2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6"
NK_VERSION="0.7.5"

rm -rf upstream lua-src artifacts
mkdir -p artifacts

echo "== Fetch pinned upstream =="
git init upstream
git -C upstream remote add origin "$UPSTREAM_REPO"
git -C upstream fetch --depth 1 origin "$UPSTREAM_SHA"
git -C upstream checkout --detach FETCH_HEAD
git -C upstream submodule update --init --recursive

echo "== Toolchain =="
brew install ldid 2>/dev/null || true
SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"

echo "== Build native NKTouch helpers =="
xcrun --sdk iphoneos clang -Os -Wall -Wextra -Werror -arch arm64 -miphoneos-version-min=15.0 -isysroot "$SDKROOT" runtime/nktouch-native.c -o runtime/nktouch-native
clang -std=c11 -Wall -Wextra -fsyntax-only runtime/nktask.c
xcrun --sdk iphoneos clang -std=c11 -Os -Wall -Wextra -arch arm64 -miphoneos-version-min=15.0 -isysroot "$SDKROOT" runtime/nktask.c -o runtime/nktask
xcrun --sdk iphoneos clang -fobjc-arc -Os -Wall -Wextra -Werror -arch arm64 -miphoneos-version-min=15.0 -isysroot "$SDKROOT" runtime/nkhttp.m -framework Foundation -o runtime/nkhttp
chmod 755 runtime/nktouch-native runtime/nktask runtime/nkhttp runtime/nktouchctl-v7 runtime/nkrecorder runtime/nkeditor runtime/nkbundle runtime/nknetwork runtime/nktouch-lua
ldid -S runtime/nktouch-native
ldid -S runtime/nktask
ldid -S runtime/nkhttp

echo "== Fetch Lua $LUA_VERSION =="
curl -fsSL "https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz" -o /tmp/lua-v075.tar.gz
printf '%s  %s\n' "$LUA_SHA256" /tmp/lua-v075.tar.gz | shasum -a 256 -c -
mkdir lua-src
tar -xzf /tmp/lua-v075.tar.gz -C lua-src --strip-components=1
cp lua-src/README runtime/LUA_README.txt

python3 - <<'PY'
from pathlib import Path
src=Path('lua-src/src/linit.c').read_text()
include='#include "lualib.h"\n'
if include not in src:
    raise SystemExit('linit include marker missing')
src=src.replace(include, include+'\nextern int luaopen_nkcore(lua_State *L);\n', 1)
marker='  {NULL, NULL}\n'
if marker not in src:
    raise SystemExit('linit library marker missing')
src=src.replace(marker, '  {"nkcore", luaopen_nkcore},\n'+marker, 1)
Path('runtime/linit-nktouch.c').write_text(src)
PY

echo "== Host smoke test =="
COMMON=$(find lua-src/src -maxdepth 1 -type f -name '*.c' ! -name 'lua.c' ! -name 'luac.c' ! -name 'linit.c' -print | sort | tr '\n' ' ')
clang -O2 -Ilua-src/src -DLUA_USE_POSIX $COMMON runtime/linit-nktouch.c runtime/nkcore.c lua-src/src/lua.c -lm -o /tmp/nktouch-lua-host-v075
/tmp/nktouch-lua-host-v075 -e 'package.path="lua/?.lua;"..package.path; local n=require("nktouch"); assert(n.VERSION=="0.6.4" and n.DIRECT==true)'
/tmp/nktouch-lua-host-v075 -e 'package.path="lua/?.lua;"..package.path; local j=require("nkjson"); local s=assert(j.encode({ok=true,items=j.array({1,2,3})})); local t=assert(j.decode(s)); assert(t.ok==true and t.items[3]==3)'

echo "== Build bundled Lua 5.4.9 for iOS =="
COMMON_NK=$(find lua-src/src -maxdepth 1 -type f -name '*.c' ! -name 'lua.c' ! -name 'luac.c' ! -name 'linit.c' -print | sort | tr '\n' ' ')
COMMON_LUAC=$(find lua-src/src -maxdepth 1 -type f -name '*.c' ! -name 'lua.c' ! -name 'luac.c' ! -name 'linit.c' -print | sort | tr '\n' ' ')
LUA_FLAGS="-Os -arch arm64 -miphoneos-version-min=15.0 -isysroot $SDKROOT -Ilua-src/src -DLUA_USE_POSIX -Dl_system=nktouch_lua_system -Dl_popen=nktouch_lua_popen -Dl_pclose=nktouch_lua_pclose -include $ROOT/runtime/lua-ios-shim.h"
xcrun --sdk iphoneos clang $LUA_FLAGS $COMMON_NK runtime/linit-nktouch.c runtime/nkcore.c runtime/lua-ios-shim.c lua-src/src/lua.c -lm -Wl,-dead_strip -o runtime/lua54
xcrun --sdk iphoneos clang $LUA_FLAGS $COMMON_LUAC runtime/lua-ios-shim.c lua-src/src/luac.c -lm -Wl,-dead_strip -o runtime/luac54
chmod 755 runtime/lua54 runtime/luac54
ldid -S runtime/lua54
ldid -S runtime/luac54

echo "== Contract tests =="
python3 -m unittest tests/test_v064_contract.py -v
python3 -m unittest tests/test_v072_contract.py -v
python3 -m unittest tests/test_v073_contract.py -v
python3 -m unittest tests/test_v074_contract.py -v
python3 -m py_compile scripts/apply-v741-video-ux.py scripts/apply-v075-editor-runner-console.py
bash -n scripts/prepare-v0741-video-ux.sh
bash -n scripts/prepare-v075-editor-runner-console.sh

echo "== Apply V7.5 source layer =="
bash scripts/prepare-v075-editor-runner-console.sh upstream
SETTINGS="upstream/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
grep -Fq '// NKTouch V7.5 Editor + Runner + Console' "$SETTINGS"
grep -Fq 'NK75LineNumberView' "$SETTINGS"
grep -Fq 'nk75_refreshRuntime' "$SETTINGS"
grep -q '^Version: 0.7.5$' upstream/control
grep -Fq 'NKTouch 0.7.5 Editor + Runner + Console' upstream/layout/usr/share/doc/nktouch/VERSION

echo "== Upstream tests =="
(
  cd upstream
  python3 -m unittest discover -s tests -v
)

echo "== Build iOS application =="
(
  cd upstream
  set -o pipefail
  xcodebuild -project zxtouch/zxtouch.xcodeproj -target zxtouch -sdk iphoneos -configuration Release \
    SYMROOT="$(pwd)/app-build" ONLY_ACTIVE_ARCH=NO ARCHS="arm64 arm64e" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=YES PRODUCT_BUNDLE_IDENTIFIER=com.zjx.zxtouch \
    2>&1 | tee xcode_build.log

  APP=$(find ./app-build -name 'zxtouch.app' -type d | head -1)
  test -n "$APP"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName NKTouch' "$APP/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string NKTouch' "$APP/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName NKTouch' "$APP/Info.plist" 2>/dev/null || true
  ldid -Szxtouch/app-entitlements.plist "$APP/zxtouch"
  EXT="$APP/PlugIns/shortcutext.appex/shortcutext"
  if [[ -f "$EXT" ]]; then ldid -Szxtouch/shortcutext-entitlements.plist "$EXT"; fi
  rm -rf layout/Applications/zxtouch.app
  cp -r "$APP" layout/Applications/zxtouch.app
)

echo "== Setup rootless Theos =="
export THEOS="$ROOT/upstream/theos"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)"

echo "== Build rootless package =="
(
  cd upstream
  make clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
)

DEB=$(python3 - <<'PY'
from pathlib import Path
files=[p for p in Path('upstream/packages').rglob('*.deb') if p.is_file()]
if not files:
    raise SystemExit('No .deb produced')
print(max(files,key=lambda p:p.stat().st_mtime))
PY
)
OUT="artifacts/com.nk.nktouch_${NK_VERSION}_rootless.deb"
cp "$DEB" "$OUT"
test -s "$OUT"
echo "Built: $OUT"
ls -lah artifacts
