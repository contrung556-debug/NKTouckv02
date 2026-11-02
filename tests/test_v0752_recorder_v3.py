from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RecorderV3Contract(unittest.TestCase):
    def test_runtime_has_segment_pause_resume_timeline_lifecycle(self):
        s = (ROOT / "runtime/nkrecorder-v3").read_text()
        self.assertIn('VERSION="0.7.5.2"', s)
        for marker in (
            'pause)', 'resume)', 'stop)', 'inspect)', 'edit)', 'delete)',
            'move)', 'render)', 'test)', 'SEGMENTS=', 'append_current_segment',
            'start_segment', 'merged.raw', 'exec "$TASK" start',
        ):
            self.assertIn(marker, s)
        self.assertIn('/var/mobile/Library/NKTouch/scripts', s)
        self.assertIn('/var/mobile/Library/NKTouch/recordings', s)

    def test_exporter_has_bounded_editable_timeline(self):
        s = (ROOT / "lua/nkrecorder_v3.lua").read_text()
        self.assertIn('local VERSION = "0.7.5.2"', s)
        for marker in (
            'timeline_from_raw', 'read_timeline', 'write_timeline', 'render_lua',
            'local function edit(', 'local function delete_row(', 'local function move_row(',
            'MAX_ACTION_MS = 300000', 'MAX_DELAY_MS = 300000', 'MAX_COORD = 10000',
            'local nk = require(\\"nktouch_v7\\")',
        ):
            self.assertIn(marker, s)
        self.assertRegex(s, r'action=true.*idle_ms=true.*duration_ms=true.*x1=true.*y1=true')

    def test_ui_patch_exposes_daily_driver_controls(self):
        s = (ROOT / "scripts/apply-v0752-recorder-v3.py").read_text()
        for marker in (
            'NKRecorderV3ViewController', 'Record • Pause • Timeline',
            'recordTapped', 'pauseResumeTapped', 'stopTapped', 'reloadTimeline',
            'showEditMenu', 'editTimingAt', 'editCoordsAt', 'moveRow', 'deleteRow',
            'testTapped', 'convertTapped', 'Convert → Lua', 'NKTaskDetailViewController',
        ):
            self.assertIn(marker, s)

    def test_prepare_layers_on_daily_driver_without_mutating_core_contract(self):
        s = (ROOT / "scripts/prepare-v0752-recorder-v3.sh").read_text()
        self.assertIn('prepare-v0747-daily-driver.sh', s)
        self.assertIn('runtime/nkrecorder-v3', s)
        self.assertIn('lua/nkrecorder_v3.lua', s)
        self.assertIn('Version: 0.7.5.2', s)
        # V3 must not patch the native task supervisor source.
        self.assertNotIn('nktask.c', s)


if __name__ == "__main__":
    unittest.main()
