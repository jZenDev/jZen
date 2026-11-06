"""Plant capability regressions rather than checking the gate against itself."""
import importlib.util
import json
import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('demo_network', SCRIPT_ROOT / 'verify-demo-network.py')
network = importlib.util.module_from_spec(spec)
spec.loader.exec_module(network)


class DemoNetworkTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        source = SCRIPT_ROOT.parent
        app = self.root / network.DEMO
        for relative in (
            'ios/Runner/Info.plist', 'macos/Runner/Info.plist',
            'macos/Runner/DebugProfile.entitlements', 'macos/Runner/Release.entitlements',
            'macos/Runner/Profile.entitlements',
            'ios/Flutter/Debug.xcconfig', 'ios/Flutter/Release.xcconfig', 'lib/main.dart',
            'android/app/src/main/AndroidManifest.xml',
            'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
        ):
            target = app / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(source / network.DEMO / relative, target)
        shutil.copy(source / 'Taskfile.yml', self.root / 'Taskfile.yml')
        (self.root / 'apps/pubspec.lock').write_text('\n'.join(
            f'  {name}:\n    version: "{version}"' for name, version in network.REVIEWED_APPLE_VERSIONS.items()))
        for package in ('zen_core', 'zen_transport', 'zen_identity', 'zen_secure_store',
                        'zen_ui_identity', 'zen_ui_navigation', 'zen_ui_widgets'):
            directory = self.root / 'client' / package / 'lib'
            directory.mkdir(parents=True)
            (directory / 'fixture.dart').write_text('library;\n')

    def test_reviewed_configuration_passes(self):
        self.assertEqual([], network.check(self.root))

    def test_source_bonjour_declaration_fails(self):
        path = self.root / network.DEMO / 'macos/Runner/Info.plist'
        data = plistlib.loads(path.read_bytes())
        data['NSBonjourServices'] = ['_dartVmService._tcp']
        path.write_bytes(plistlib.dumps(data))
        self.assertTrue(any('NSBonjourServices' in e for e in network.check(self.root)))

    def test_release_listener_or_extra_capability_fails(self):
        path = self.root / network.DEMO / 'macos/Runner/Release.entitlements'
        data = plistlib.loads(path.read_bytes())
        data['com.apple.security.network.server'] = True
        path.write_bytes(plistlib.dumps(data))
        self.assertTrue(any('network.server' in e for e in network.check(self.root)))

    def test_removed_launch_flag_fails(self):
        path = self.root / 'Taskfile.yml'
        path.write_text(path.read_text().replace('--no-publish-port', ''))
        self.assertTrue(any('launcher' in e for e in network.check(self.root)))

    def test_xcode_profile_launch_must_disable_vm_service_publication(self):
        path = self.root / network.DEMO / 'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme'
        source = path.read_text()
        profile = network.re.search(r'<ProfileAction\b[^>]*>(.*?)</ProfileAction>', source, network.re.S)
        arguments = network.re.search(r'<CommandLineArguments>.*?</CommandLineArguments>', profile.group(1), network.re.S)
        replacement = profile.group(1).replace(arguments.group(0), '', 1)
        path.write_text(source[:profile.start(1)] + replacement + source[profile.end(1):])
        self.assertTrue(any('ProfileAction' in e for e in network.check(self.root)))

    def test_bypass_socket_in_framework_fails(self):
        path = self.root / 'client/zen_identity/lib/fixture.dart'
        path.write_text("final socket = Socket.connect(host, port);\n")
        self.assertTrue(any('unreviewed raw socket' in e for e in network.check(self.root)))

    def test_new_plugin_or_missing_platform_inventory_fails(self):
        inventory = self.root / network.DEMO / '.flutter-plugins-dependencies'
        inventory.write_text(json.dumps({'plugins': {'ios': [{'name': 'bonsoir'}], 'macos': []}}))
        self.assertTrue(any('bonsoir' in e for e in network.check(self.root)))
        self.assertTrue(network.check_plugins({'plugins': {}}))

    def test_missing_scope_fails(self):
        (self.root / 'client/zen_core/lib/fixture.dart').unlink()
        self.assertTrue(any('empty audit scope' in e for e in network.check(self.root)))

    def test_plugin_upgrade_requires_another_review(self):
        path = self.root / 'apps/pubspec.lock'
        path.write_text(path.read_text().replace('7.2.1', '7.2.2'))
        self.assertTrue(any('version changed' in e for e in network.check(self.root)))

    def test_android_nearby_permission_fails_and_internet_is_required(self):
        path = self.root / network.DEMO / 'android/app/src/main/AndroidManifest.xml'
        source = path.read_text()
        path.write_text(source.replace('android.permission.INTERNET', 'android.permission.NEARBY_WIFI_DEVICES'))
        errors = network.check(self.root)
        self.assertTrue(any('unreviewed Android' in e for e in errors))
        self.assertTrue(any('release too' in e for e in errors))

    def test_built_plist_is_checked_independently_of_source(self):
        self.assertTrue(network.check_plist({'NSLocalNetworkUsageDescription': 'debug'}, 'built app'))
        self.assertTrue(network.check_entitlements({'com.apple.security.network.client': True}, 'app', False))
