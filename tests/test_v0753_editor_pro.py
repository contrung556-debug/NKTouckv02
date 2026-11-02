from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APPLY = ROOT / 'scripts' / 'apply-v0753-editor-pro.py'
PREP = ROOT / 'scripts' / 'prepare-v0753-editor-pro.sh'
API = ROOT / 'runtime' / 'nktouch-api.tsv'
REC = ROOT / 'runtime' / 'nkrecorder-v3'

class EditorProContract(unittest.TestCase):
    def test_apply_contains_editor_pro_features(self):
        s = APPLY.read_text()
        for marker in (
            'setupEditorPro',
            'updateLineNumbers',
            'showFindReplace',
            'replaceAll:',
            'showSnippetMenu',
            'scheduleAutosave',
            'backupCurrentIfNeeded',
            'showBackupMenu',
            '/var/mobile/Library/NKTouch/backups',
            'Editor ▾',
            'nk.http.get',
        ):
            self.assertIn(marker, s)

    def test_prepare_preserves_runtime_and_recorder(self):
        s = PREP.read_text()
        self.assertIn('prepare-v0752-recorder-v3.sh', s)
        self.assertIn("Version: 0.7.5.3", s)
        self.assertIn('/var/jb/usr/libexec/nktouch/lua54', s)
        self.assertIn('VERSION="0.7.5.2"', s)
        self.assertNotIn('install -m 0755 "$ROOT/runtime/nktask', s)

    def test_snippets_match_api_catalog(self):
        api = API.read_text()
        for name in ('nk.tap|', 'nk.sleep|', 'nk.swipe|', 'nk.text|', 'nk.http.get|'):
            self.assertIn(name, api)

    def test_recorder_v3_baseline_present(self):
        s = REC.read_text()
        self.assertIn('VERSION="0.7.5.2"', s)
        for cmd in ('pause)', 'resume)', 'inspect)', 'edit)', 'render)', 'test)'):
            self.assertIn(cmd, s)

if __name__ == '__main__':
    unittest.main()
