from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class V074NetworkContract(unittest.TestCase):
    def text(self, rel):
        return (ROOT / rel).read_text()

    def test_wrapper_exposes_network_and_retains_previous_layers(self):
        s = self.text("runtime/nktouchctl-v7")
        self.assertIn('VERSION="0.7.4"', s)
        self.assertIn('NETWORK="/var/jb/usr/bin/nknetwork"', s)
        self.assertIn('network|http)', s)
        self.assertIn('BUNDLE="/var/jb/usr/bin/nkbundle"', s)
        self.assertIn('EDITOR="/var/jb/usr/bin/nkeditor"', s)
        self.assertIn('RECORDER="/var/jb/usr/bin/nkrecorder"', s)
        self.assertIn('TASK="/var/jb/usr/bin/nktask"', s)
        self.assertIn('OCR remains explicit/on-demand only', s)

    def test_native_http_is_streaming_bounded_and_tls_safe(self):
        s = self.text("runtime/nkhttp.m")
        self.assertIn('NKMaxBodyBytes = 16u * 1024u * 1024u', s)
        self.assertIn('NKMaxResponseBytes = 32u * 1024u * 1024u', s)
        self.assertIn('NSURLSessionDataDelegate', s)
        self.assertIn('didReceiveData', s)
        self.assertIn('response exceeds configured size limit', s)
        self.assertIn('ephemeralSessionConfiguration', s)
        self.assertIn('Never downgrade HTTPS to cleartext through redirects', s)
        self.assertNotIn('allowsAnyHTTPSCertificate', s)
        self.assertNotIn('serverTrust', s)
        self.assertNotIn('credentialForTrust', s)
        self.assertNotIn('NSLog(', s)

    def test_lua_network_is_explicit_no_auto_retry_and_secret_argv_safe(self):
        s = self.text("lua/nknet.lua")
        self.assertIn('function M.request(opts)', s)
        self.assertIn('function M.get(url,opts)', s)
        self.assertIn('function M.post(url,body,opts)', s)
        self.assertIn('function M.download(url,path,opts)', s)
        self.assertIn('function M.upload(url,path,opts)', s)
        self.assertIn('headers_file=', s)
        self.assertIn('body_file=', s)
        self.assertIn('shq(HELPER).." request "..shq(spec)', s)
        self.assertNotIn('Authorization', s)
        self.assertNotIn('for attempt=', s)
        self.assertNotIn('retry', s.lower())

    def test_json_codec_is_bounded_and_dependency_free(self):
        s = self.text("lua/nkjson.lua")
        self.assertIn('M.VERSION = "0.7.4"', s)
        self.assertIn('if depth>64', s)
        self.assertIn('JSON circular table', s)
        self.assertIn('function M.encode(v)', s)
        self.assertIn('function M.decode(s)', s)
        self.assertIn('function M.array(t)', s)
        self.assertIn('function M.object(t)', s)
        self.assertNotIn('os.execute', s)
        self.assertNotIn('io.popen', s)

    def test_v7_extension_attaches_network_without_replacing_v64_core(self):
        s = self.text("lua/nktouch_v7.lua")
        self.assertIn('local nk=require("nktouch")', s)
        self.assertIn('nk.http=require("nknet")', s)
        self.assertIn('nk.json=require("nkjson")', s)
        self.assertIn('nk.NETWORK_VERSION="0.7.4"', s)
        base = self.text("lua/nktouch.lua")
        self.assertIn('M.VERSION="0.6.4"', base)
        runner = self.text("runtime/nktouch-lua")
        self.assertIn('require("nktouch_v7")', runner)

    def test_network_controller_has_local_doctor_without_external_probe(self):
        s = self.text("runtime/nknetwork")
        self.assertIn('VERSION="0.7.4"', s)
        self.assertIn('doctor)', s)
        self.assertIn('request)', s)
        self.assertIn('tls=system-validation', s)
        self.assertIn('mode=on-demand', s)
        self.assertNotIn('curl ', s)
        self.assertNotIn('https://example.com', s)

    def test_api_catalog_exposes_network_and_json(self):
        s = self.text("runtime/nktouch-api.tsv")
        for api in (
            'nk.http.request|', 'nk.http.get|', 'nk.http.post|',
            'nk.http.download|', 'nk.http.upload|',
            'nk.json.encode|', 'nk.json.decode|', 'nk.json.array|', 'nk.json.object|'
        ):
            self.assertIn(api, s)

    def test_package_layer_preserves_protocol_ids(self):
        s = self.text("scripts/prepare-v074.sh")
        for line in (
            'TASK_TOUCH_RECORDING_START 14',
            'TASK_TOUCH_RECORDING_STOP 15',
            'TASK_TEXT_RECOGNIZER 27',
            'TASK_PROMPT_INPUT 29',
            'TASK_SCREENSHOT 30',
        ):
            self.assertIn(line, s)
        self.assertIn('nkhttp', s)
        self.assertIn('nknetwork', s)
        self.assertIn('nkjson.lua', s)
        self.assertIn('nknet.lua', s)
        self.assertIn('nktouch_v7.lua', s)

    def test_previous_v7_layers_remain_versioned(self):
        self.assertIn('#define VERSION "0.7.0"', self.text("runtime/nktask.c"))
        self.assertIn('VERSION="0.7.1"', self.text("runtime/nkrecorder"))
        self.assertIn('VERSION="0.7.2"', self.text("runtime/nkeditor"))
        self.assertIn('VERSION="0.7.3"', self.text("runtime/nkbundle"))
        self.assertIn('local VERSION = "0.7.1"', self.text("lua/nkrecorder.lua"))


if __name__ == "__main__":
    unittest.main()
