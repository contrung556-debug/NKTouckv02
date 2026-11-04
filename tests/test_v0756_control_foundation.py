from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class V0756ControlFoundationContract(unittest.TestCase):
    def text(self, rel):
        return (ROOT / rel).read_text()

    def test_hotkey_tweak_keeps_v5_volume_hold_and_adds_dispatcher(self):
        s = self.text('patches/NKTouchHotkeyEngine.xm')
        self.assertIn('SBVolumeHardwareButton', s)
        self.assertIn('NKHotkeyHoldDelay = 0.5', s)
        self.assertIn('NKHotkeyActionRecorderFinish', s)
        self.assertIn('NKDispatchHotkeyAction', s)
        self.assertIn('notify_post(NKRecorderVolumeHoldNotification)', s)
        self.assertIn('%orig;', s)

    def test_feedback_window_lookup_avoids_deprecated_uikit_property(self):
        s = self.text('patches/NKTouchHotkeyEngine.xm')
        self.assertIn('@available(iOS 13.0, *)', s)
        self.assertIn('application.connectedScenes', s)
        self.assertIn('windowScene.windows', s)
        self.assertIn('[application valueForKey:@"windows"]', s)
        self.assertNotIn('UIApplication.sharedApplication.windows', s)

    def test_feedback_is_completion_driven_not_fake_recorder_state(self):
        s = self.text('patches/NKTouchHotkeyEngine.xm')
        self.assertIn('com.nk.nktouch.recorder.accepted', s)
        self.assertIn('com.nk.nktouch.recorder.completed.ok', s)
        self.assertIn('com.nk.nktouch.recorder.completed.failed', s)
        self.assertIn('REC STOPPING', s)
        self.assertIn('REC SAVED', s)
        self.assertIn('REC ERROR', s)
        self.assertIn('UINotificationFeedbackGenerator', s)
        self.assertNotIn('/var/mobile/Library/NKTouch/recorder-v3/mode', s)

    def test_runner_patch_adds_accepted_and_result_channels(self):
        s = self.text('scripts/apply-v0756-control-foundation.py')
        self.assertIn('kNKRecorderAcceptedNotification', s)
        self.assertIn('kNKRecorderCompletedOKNotification', s)
        self.assertIn('kNKRecorderCompletedFailedNotification', s)
        self.assertIn('notify_post(kNKRecorderAcceptedNotification)', s)
        self.assertIn('code == 0 ? kNKRecorderCompletedOKNotification : kNKRecorderCompletedFailedNotification', s)

    def test_package_version_is_separate_from_retained_network_component(self):
        s = self.text('runtime/nktouchctl-v7')
        self.assertIn('PACKAGE_VERSION="0.7.5.6"', s)
        self.assertIn('VERSION="0.7.4"', s)
        self.assertIn('version --all', s)
        self.assertIn('package=$PACKAGE_VERSION', s)
        self.assertIn('network=$VERSION', s)

    def test_prepare_layers_on_v5_and_keeps_rootless_layout_clean(self):
        s = self.text('scripts/prepare-v0756-control-foundation.sh')
        self.assertIn('prepare-v0755-recorder-v5-volume.sh', s)
        self.assertIn('apply-v0756-control-foundation.py', s)
        self.assertIn('Version: 0.7.5.6', s)
        self.assertIn('test ! -e "$SRC/layout/var/jb"', s)
        self.assertIn('Touch-point indicator is intentionally deferred', s)


if __name__ == '__main__':
    unittest.main()
