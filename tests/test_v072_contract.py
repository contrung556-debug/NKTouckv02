from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class V072ScriptEditorContract(unittest.TestCase):
    def text(self, rel):
        return (ROOT / rel).read_text()

    def test_wrapper_exposes_editor_and_retains_previous_layers(self):
        s = self.text("runtime/nktouchctl-v7")
        self.assertRegex(s, r'VERSION="0\.7\.[23]"')
        self.assertIn('EDITOR="/var/jb/usr/bin/nkeditor"', s)
        self.assertIn('RECORDER="/var/jb/usr/bin/nkrecorder"', s)
        self.assertIn('TASK="/var/jb/usr/bin/nktask"', s)
        self.assertIn('editor|script)', s)
        self.assertIn('exec "$EDITOR" "$@"', s)
        self.assertIn('OCR remains explicit/on-demand only', s)

    def test_editor_has_workspace_lifecycle_and_run_controls(self):
        s = self.text("runtime/nkeditor")
        self.assertIn('VERSION="0.7.2"', s)
        self.assertIn('/var/mobile/Library/NKTouch/scripts', s)
        for command in (
            'new)', 'import)', 'clone)', 'list)', 'path)', 'show)', 'check)',
            'edit)', 'append)', 'delete)', 'api)', 'complete)', 'snippet)',
            'run)', 'status)', 'pause)', 'resume)', 'stop)', 'logs)', 'doctor)'
        ):
            self.assertIn(command, s)
        self.assertIn('nano micro vim vi', s)

    def test_syntax_check_is_mandatory_before_run_and_safe_edits(self):
        s = self.text("runtime/nkeditor")
        self.assertIn('"$LUAC" -p "$file"', s)
        self.assertIn('refusing to run script with syntax errors', s)
        self.assertLess(s.index('"$LUAC" -p "$file" || { echo "NKTouch Editor: refusing to run script with syntax errors"'), s.index('exec "$TASK" start "$file" "$@"'))
        self.assertIn('append_checked()', s)
        self.assertIn('mv "$backup" "$file"', s)
        self.assertIn('script was not left partially edited', s)
        self.assertIn('rc=$?', s)
        self.assertIn('exit "$rc"', s)

    def test_template_failures_keep_the_original_exit_status(self):
        s = self.text("runtime/nkeditor")
        self.assertIn('emit_template "$template" > "$tmp" || rc=$?', s)
        self.assertIn('if [ "$rc" -ne 0 ]; then rm -f "$tmp"; exit "$rc"; fi', s)

    def test_managed_script_names_block_path_escape(self):
        s = self.text("runtime/nkeditor")
        self.assertIn('case "$n" in */*|.*|*..*) return 1 ;; esac', s)
        self.assertIn("tr -cd 'A-Za-z0-9._-'", s)
        self.assertIn('SCRIPTS="/var/mobile/Library/NKTouch/scripts"', s)

    def test_api_catalog_supports_help_completion_and_snippets(self):
        s = self.text("runtime/nktouch-api.tsv")
        for api in ('nk.tap|', 'nk.swipe|', 'nk.waitImage|', 'nk.tapColor|', 'nk.ocr|', 'nk.waitText|'):
            self.assertIn(api, s)
        editor = self.text("runtime/nkeditor")
        self.assertIn('api_query()', editor)
        self.assertIn('complete_api()', editor)
        self.assertIn('snippet_line()', editor)
        self.assertIn("index($1,p)==1", editor)

    def test_templates_are_explicit_and_ocr_is_not_background(self):
        s = self.text("runtime/nkeditor")
        for template in ('blank)', 'tap)', 'image)', 'color)', 'ocr)'):
            self.assertIn(template, s)
        self.assertIn('OCR runs only because this script explicitly calls nk.ocr.', s)
        self.assertNotIn('ocr watcher', s.lower())
        self.assertNotIn('background ocr', s.lower())

    def test_v70_task_and_v71_recorder_are_retained(self):
        task = self.text("runtime/nktask.c")
        recorder = self.text("runtime/nkrecorder")
        exporter = self.text("lua/nkrecorder.lua")
        self.assertIn('#define VERSION "0.7.0"', task)
        self.assertIn('Only one screen-control task may be active at a time', task)
        self.assertIn('VERSION="0.7.1"', recorder)
        self.assertIn('local VERSION = "0.7.1"', exporter)

    def test_package_layer_preserves_protocol_ids(self):
        s = self.text("scripts/prepare-v072.sh")
        for line in (
            'TASK_TOUCH_RECORDING_START 14',
            'TASK_TOUCH_RECORDING_STOP 15',
            'TASK_TEXT_RECOGNIZER 27',
            'TASK_PROMPT_INPUT 29',
            'TASK_SCREENSHOT 30',
        ):
            self.assertIn(line, s)
        self.assertIn('nkeditor', s)
        self.assertIn('nktouch-api.tsv', s)
        self.assertIn('/var/mobile/Library/NKTouch/scripts', s)


if __name__ == "__main__":
    unittest.main()
