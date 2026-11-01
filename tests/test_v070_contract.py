from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class V070TaskEngineContract(unittest.TestCase):
    def text(self, rel):
        return (ROOT / rel).read_text()

    def test_task_engine_version_and_process_control(self):
        s = self.text("runtime/nktask.c")
        self.assertIn('#define VERSION "0.7.0"', s)
        self.assertIn('SIGSTOP', s)
        self.assertIn('SIGCONT', s)
        self.assertIn('SIGTERM', s)
        self.assertIn('SIGKILL', s)
        self.assertIn('posix_spawn', s)
        self.assertIn('waitpid', s)

    def test_single_active_task_guard(self):
        s = self.text("runtime/nktask.c")
        self.assertIn('#define ACTIVE TASKS "/active"', s)
        self.assertIn('O_EXCL', s)
        self.assertIn('another task is active', s)
        self.assertIn('Only one screen-control task may be active at a time', s)

    def test_task_lifecycle_and_history(self):
        s = self.text("runtime/nktask.c")
        for state in ("starting", "running", "paused", "stopping", "success", "failed", "stopped", "timeout"):
            self.assertIn(f'"{state}"', s)
        self.assertIn('.state', s)
        self.assertIn('.log', s)
        self.assertIn('started_at=', s)
        self.assertIn('ended_at=', s)
        self.assertIn('exit_code=', s)

    def test_timeout_is_bounded_and_pause_aware(self):
        s = self.text("runtime/nktask.c")
        self.assertIn('#define MAX_TIMEOUT 86400L', s)
        self.assertIn('deadline += now_sec() - paused_at', s)
        self.assertIn('timed_out', s)

    def test_lua_is_syntax_checked_before_start(self):
        s = self.text("runtime/nktask.c")
        self.assertIn('luac54', s)
        self.assertIn('Lua syntax check failed', s)
        self.assertLess(s.index('syntax_check(script)'), s.index('claim_active(id)'))

    def test_no_automatic_ocr_in_task_manager(self):
        s = self.text("runtime/nktask.c").lower()
        self.assertNotIn('task_ocr', s)
        self.assertNotIn('wait-text', s)
        self.assertNotIn('text_recognizer', s)
        wrapper = self.text("runtime/nktouchctl-v7")
        self.assertIn('OCR remains on-demand only', wrapper)

    def test_v7_wrapper_preserves_v64_runtime_commands(self):
        s = self.text("runtime/nktouchctl-v7")
        self.assertIn('VERSION="0.7.0"', s)
        self.assertIn('exec "$TASK" "$@"', s)
        self.assertIn('exec "$CORE" "$cmd" "$@"', s)
        self.assertIn('nktouchctl task start', s)
        self.assertIn('nktouchctl task pause', s)
        self.assertIn('nktouchctl task resume', s)
        self.assertIn('nktouchctl task stop', s)

    def test_packaging_keeps_protocol_ids_unchanged(self):
        s = self.text("scripts/prepare-v070.sh")
        for line in (
            'TASK_SHOW_TOAST 22',
            'TASK_COLOR_PICKER 23',
            'TASK_TEXT_RECOGNIZER 27',
            'TASK_COLOR_SEARCHER 28',
            'TASK_PROMPT_INPUT 29',
            'TASK_SCREENSHOT 30',
        ):
            self.assertIn(line, s)
        self.assertIn('OCR remains explicit/on-demand only', s)
        self.assertIn('nktask', s)
        self.assertIn('nktouchctl-core', s)


if __name__ == "__main__":
    unittest.main()
