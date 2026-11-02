#!/usr/bin/env bash
set -euo pipefail

SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIGINAL="$ROOT/patches/NKLuaWorkspace.m.inc"
PATCHED="$(mktemp)"
BACKUP="$(mktemp)"

cp "$ORIGINAL" "$BACKUP"
cleanup() {
  cp "$BACKUP" "$ORIGINAL" 2>/dev/null || true
  rm -f "$BACKUP" "$PATCHED"
}
trap cleanup EXIT

python3 "$ROOT/scripts/ux-hotfix-v0741.py" "$ORIGINAL" "$PATCHED"
cp "$PATCHED" "$ORIGINAL"

# Reuse the established V7.4.1 packaging/network path; only the workspace source
# is temporarily replaced by the video-reviewed UX build for this invocation.
bash "$ROOT/scripts/prepare-v074.sh" "$SRC"

echo "--- NKTouch v0.7.4.1 video UX hotfix applied ---"
