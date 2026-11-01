from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class V073TaskBundleContract(unittest.TestCase):
    def text(self, rel):
        return (ROOT / rel).read_text()

    def test_wrapper_exposes_bundle_and_retains_layers(self):
        s = self.text("runtime/nktouchctl-v7")
        self.assertIn('VERSION="0.7.3"', s)
        self.assertIn('BUNDLE="/var/jb/usr/bin/nkbundle"', s)
        self.assertIn('bundle|pack)', s)
        self.assertIn('EDITOR="/var/jb/usr/bin/nkeditor"', s)
        self.assertIn('RECORDER="/var/jb/usr/bin/nkrecorder"', s)
        self.assertIn('TASK="/var/jb/usr/bin/nktask"', s)
        self.assertIn('OCR remains explicit/on-demand only', s)

    def test_bundle_controller_has_export_import_and_asset_lifecycle(self):
        s = self.text("runtime/nkbundle")
        self.assertIn('VERSION="0.7.3"', s)
        for command in ('asset)', 'export)', 'inspect)', 'import|install)', 'list)', 'doctor)'):
            self.assertIn(command, s)
        self.assertIn('ROOT="/var/mobile/Library/NKTouch"', s)
        self.assertIn('ASSETS="$ROOT/assets"', s)
        self.assertIn('BUNDLES="$ROOT/bundles"', s)
        self.assertIn('refusing to export script with syntax errors', s)
        self.assertIn('imported script failed syntax check', s)
        self.assertIn('output already exists', s)
        self.assertIn('script already exists', s)

    def test_container_is_dependency_free_and_bounded(self):
        s = self.text("lua/nkbundle.lua")
        self.assertIn('local MAGIC = "NKTASK1"', s)
        self.assertIn('local MAX_FILES = 128', s)
        self.assertIn('local MAX_FILE = 16 * 1024 * 1024', s)
        self.assertIn('local MAX_TOTAL = 32 * 1024 * 1024', s)
        self.assertIn('local MAX_SCRIPT = 1024 * 1024', s)
        self.assertIn('fnv1a', s)
        self.assertNotIn('os.execute(', s)
        self.assertNotIn('io.popen(', s)
        self.assertNotIn('require("zip")', s)

    def test_container_blocks_path_traversal_and_duplicates(self):
        s = self.text("lua/nkbundle.lua")
        self.assertIn('if path == "script.lua" then return true end', s)
        self.assertIn('path:match("^assets/([^/]+)$")', s)
        self.assertIn('s:find("..", 1, true)', s)
        self.assertIn('duplicate entry:', s)
        self.assertIn('bundle must contain exactly one script.lua', s)
        self.assertIn('unexpected trailing data', s)

    def test_import_is_staged_and_no_overwrite(self):
        s = self.text("runtime/nkbundle")
        self.assertIn('stage="$TMP/nkbundle-import-$$"', s)
        self.assertIn('mkdir -p "$stage/assets"', s)
        self.assertIn('"$LUA" "$PACKER" extract "$bundle" "$stage"', s)
        self.assertIn('"$LUAC" -p "$stage/script.lua"', s)
        self.assertIn('[ ! -e "$dst_script" ]', s)
        self.assertIn('[ ! -e "$dst_assets" ]', s)

    def test_package_layer_preserves_protocol_ids(self):
        s = self.text("scripts/prepare-v073.sh")
        for line in (
            'TASK_TOUCH_RECORDING_START 14',
            'TASK_TOUCH_RECORDING_STOP 15',
            'TASK_TEXT_RECOGNIZER 27',
            'TASK_PROMPT_INPUT 29',
            'TASK_SCREENSHOT 30',
        ):
            self.assertIn(line, s)
        self.assertIn('nkbundle.lua', s)
        self.assertIn('/var/mobile/Library/NKTouch/assets', s)
        self.assertIn('/var/mobile/Library/NKTouch/bundles', s)

    def test_previous_v7_layers_remain_versioned(self):
        self.assertIn('#define VERSION "0.7.0"', self.text("runtime/nktask.c"))
        self.assertIn('VERSION="0.7.1"', self.text("runtime/nkrecorder"))
        self.assertIn('VERSION="0.7.2"', self.text("runtime/nkeditor"))
        self.assertIn('local VERSION = "0.7.1"', self.text("lua/nkrecorder.lua"))


if __name__ == "__main__":
    unittest.main()
