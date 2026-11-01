from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class V071RecorderV2Contract(unittest.TestCase):
    def text(self, rel):
        return (ROOT / rel).read_text()

    def test_wrapper_exposes_recorder_without_replacing_task_engine(self):
        s = self.text("runtime/nktouchctl-v7")
        self.assertIn('VERSION="0.7.1"', s)
        self.assertIn('RECORDER="/var/jb/usr/bin/nkrecorder"', s)
        self.assertIn('exec "$RECORDER" "$@"', s)
        self.assertIn('exec "$TASK" "$@"', s)
        self.assertIn('exec "$CORE" "$cmd" "$@"', s)
        self.assertIn('OCR remains on-demand only', s)
        self.assertIn('text is not guessed', s)

    def test_recorder_controller_has_full_lifecycle(self):
        s = self.text("runtime/nkrecorder")
        self.assertIn('VERSION="0.7.1"', s)
        for command in ('start)', 'stop)', 'status)', 'export)', 'latest)', 'list)', 'doctor)'):
            self.assertIn(command, s)
        self.assertIn('/var/mobile/Library/NKTouch/recordings', s)
        self.assertIn('/var/mobile/Library/NKTouch/recorder', s)
        self.assertIn('/var/mobile/Library/ZXTouch/scripts/recording', s)
        self.assertIn('record start', s)
        self.assertIn('record stop', s)
        self.assertIn('wait_raw_stable', s)

    def test_exporter_parses_real_hid_and_emits_editable_lua(self):
        s = self.text("lua/nkrecorder.lua")
        self.assertIn('^18(%d+)$', s)
        self.assertIn('^101([012])', s)
        self.assertIn('TAP_MOVE_THRESHOLD = 18.0', s)
        self.assertIn('HOLD_THRESHOLD_MS = 450', s)
        self.assertIn('must(nk.tap(', s)
        self.assertIn('must(nk.hold(', s)
        self.assertIn('must(nk.swipe(', s)
        self.assertIn('must(nk.sleep(', s)
        self.assertIn('semantic text', s)
        self.assertNotIn('nk.ocr(', s)
        self.assertNotIn('waitText(', s)

    def test_first_idle_is_trimmed_but_inter_gesture_timing_is_kept(self):
        s = self.text("lua/nkrecorder.lua")
        self.assertIn('if #gestures == 0 then idle_ms = 0 end', s)
        self.assertIn('idle_us = pending_us', s)
        self.assertIn('g.duration_us = g.duration_us + pending_us', s)

    def test_package_keeps_protocol_ids_and_fixes_double_reply(self):
        s = self.text("scripts/prepare-v071.sh")
        self.assertIn('TASK_TOUCH_RECORDING_START 14', s)
        self.assertIn('TASK_TOUCH_RECORDING_STOP 15', s)
        self.assertIn('TASK_PROMPT_INPUT 29', s)
        self.assertIn('TASK_SCREENSHOT 30', s)
        self.assertIn('Task.xm owns the single socket response for task 14', s)
        self.assertIn("'notifyClient' in line", s)
        self.assertIn("'scriptDirectory' in line", s)
        self.assertIn("'requestClient' in line", s)
        self.assertIn("! grep -Eq 'notifyClient.*scriptDirectory.*requestClient'", s)
        self.assertIn('nkrecorder.lua', s)
        self.assertIn('recordings /var/mobile/Library/NKTouch/recorder', s)

    def test_v70_task_supervisor_is_retained(self):
        s = self.text("runtime/nktask.c")
        self.assertIn('#define VERSION "0.7.0"', s)
        self.assertIn('Only one screen-control task may be active at a time', s)
        self.assertIn('SIGSTOP', s)
        self.assertIn('SIGCONT', s)


if __name__ == "__main__":
    unittest.main()
