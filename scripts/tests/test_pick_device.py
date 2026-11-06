"""Device selection must not discover other computers or hide Flutter failures."""
import contextlib
import importlib.util
import io
import json
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('pick_device', Path(__file__).resolve().parents[1] / 'pick-device.py')
picker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(picker)


class PickDeviceTest(unittest.TestCase):
    def test_explicit_desktop_never_enumerates_devices(self):
        for target, system in [('macos', 'Darwin'), ('linux', 'Linux'), ('windows', 'Windows')]:
            with patch.dict(picker.os.environ, {'ZEN_TARGET': target, 'ZEN_PLATFORM': ''}), \
                    patch.object(picker.platform, 'system', return_value=system), \
                    patch.object(picker, 'devices') as devices, contextlib.redirect_stdout(io.StringIO()) as out:
                picker.main()
                devices.assert_not_called()
                self.assertEqual(f'{target}\t{target}\n', out.getvalue())

    def test_device_list_is_attached_only_and_no_analytics(self):
        with patch.object(picker.subprocess, 'run', return_value=CompletedProcess([], 0, '[]', '')) as run:
            self.assertEqual([], picker.devices())
            command = run.call_args.args[0]
            self.assertIn('--device-connection=attached', command)
            self.assertIn('--suppress-analytics', command)

    def test_failure_with_valid_json_is_still_a_failure(self):
        with patch.object(picker.subprocess, 'run', return_value=CompletedProcess([], 1, '[]', 'denied')), \
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            picker.devices()

    def test_chooses_explicit_usb_device_without_guessing_platform(self):
        data = [{'id': 'emulator-5554', 'name': 'Pixel', 'targetPlatform': 'android-arm64'}]
        with patch.dict(picker.os.environ, {'ZEN_TARGET': 'emulator-5554', 'ZEN_PLATFORM': ''}), \
                patch.object(picker.subprocess, 'run', return_value=CompletedProcess([], 0, json.dumps(data), '')), \
                contextlib.redirect_stdout(io.StringIO()) as out:
            picker.main()
            self.assertEqual('emulator-5554\tandroid\n', out.getvalue())
