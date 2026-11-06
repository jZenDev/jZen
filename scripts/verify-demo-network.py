#!/usr/bin/env python3
"""Check demo capabilities and built Apple bundles; no network traffic is generated.

This is a regression tripwire, not an OS firewall or proof about arbitrary plugin
code. The audit in docs/security/zen-demo-network.md defines its limits.
Python 3.9+, stdlib only.
"""
import argparse
import json
import plistlib
import re
import subprocess
from pathlib import Path

DEMO = Path('apps/zen_demo/zen_demo_client')
APPLE_PLUGINS = {'app_links', 'flutter_secure_storage_darwin', 'path_provider_foundation'}
# These are the versions whose Apple implementations were reviewed in issue 199,
# not dependency resolution inputs. A new version needs another source audit.
REVIEWED_APPLE_VERSIONS = {
    'app_links': '7.2.1', 'flutter_secure_storage_darwin': '0.3.2',
    'path_provider_foundation': '2.6.0',
}
ENTITLEMENTS = {
    'com.apple.security.app-sandbox', 'com.apple.security.network.client',
}
DEBUG_ENTITLEMENTS = {
    'com.apple.security.cs.allow-jit', 'com.apple.security.network.server',
}


def check_plist(data, label):
    errors = []
    for key in ('NSBonjourServices', 'NSLocalNetworkUsageDescription'):
        if key in data:
            errors.append(f'{label}: unexpected {key}; investigate its network behavior')
    return errors


def check_entitlements(data, label, debug):
    allowed = ENTITLEMENTS | (DEBUG_ENTITLEMENTS if debug else set())
    # Xcode injects this only in development-signed debug/profile products.
    if debug:
        allowed = allowed | {'com.apple.security.get-task-allow'}
    errors = [f'{label}: unreviewed entitlement {k}' for k in data if k not in allowed]
    errors += [f'{label}: {k} must remain enabled' for k in ENTITLEMENTS if data.get(k) is not True]
    return errors


def check_plugins(data):
    errors = []
    for platform in ('ios', 'macos'):
        if platform not in data.get('plugins', {}):
            errors.append(f'Missing {platform} plugin inventory')
            continue
        for plugin in data['plugins'][platform]:
            if plugin['name'] not in APPLE_PLUGINS:
                errors.append(f"{platform}: unaudited native plugin {plugin['name']}")
    return errors


def check(root):
    app = root / DEMO
    errors = []
    lock = (root / 'apps/pubspec.lock').read_text()
    for name, version in REVIEWED_APPLE_VERSIONS.items():
        entry = re.search(r'^  ' + re.escape(name) + r':\n(.*?)(?=^  \S|\Z)', lock, re.M | re.S)
        if not entry or not re.search(r'^    version: "' + re.escape(version) + r'"$', entry[1], re.M):
            errors.append(f'{name}: Apple plugin version changed; review its network behavior')
    for path in (app / 'android/app/src').glob('*/AndroidManifest.xml'):
        source = path.read_text()
        if '<!DOCTYPE' in source.upper():
            errors.append(f'{path}: DOCTYPE is not allowed')
            continue
        source = re.sub(r'<!--.*?-->', '', source, flags=re.S)
        permissions = set()
        for declaration in re.findall(r'<uses-permission\b[^>]*>', source):
            name = re.search(r"\bandroid:name\s*=\s*(['\"])(.*?)\1", declaration)
            permissions.add(name.group(2) if name else '<missing name>')
        if permissions - {'android.permission.INTERNET'}:
            errors.append(f'{path}: unreviewed Android permissions {sorted(permissions)}')
        if path.parent.name == 'main' and 'android.permission.INTERNET' not in permissions:
            errors.append(f'{path}: configured backend needs INTERNET in release too')
    if not (app / 'android/app/src/main/AndroidManifest.xml').is_file():
        errors.append('Missing main Android manifest')
    for platform in ('ios', 'macos'):
        path = app / platform / 'Runner/Info.plist'
        errors += check_plist(plistlib.loads(path.read_bytes()), str(path))
    for mode in ('DebugProfile', 'Profile', 'Release'):
        path = app / 'macos/Runner' / f'{mode}.entitlements'
        errors += check_entitlements(plistlib.loads(path.read_bytes()), str(path), mode != 'Release')
        if mode == 'Profile' and 'com.apple.security.cs.allow-jit' in plistlib.loads(path.read_bytes()):
            errors.append(f'{path}: AOT profile must not request JIT')
    for mode in ('Debug', 'Release'):
        path = app / 'ios/Flutter' / f'{mode}.xcconfig'
        if not re.search(r'^DISABLE_PORT_PUBLICATION\s*=\s*YES\s*$', path.read_text(), re.M):
            errors.append(f'{path}: Bonjour build injection must be disabled')
    main = (app / 'lib/main.dart').read_text()
    if main.index('installBackendNetwork(zenApiUrl)') > main.index('WidgetsFlutterBinding.ensureInitialized()'):
        errors.append('Install the network boundary before Flutter/plugins/clients')
    launcher = (root / 'Taskfile.yml').read_text()
    native = launcher.split('  run:demo:native:', 1)[1].split('\n  build:web:admin:', 1)[0]
    if '--no-publish-port' not in native:
        errors.append('Native launcher must disable debugger Bonjour publication')
    if '--device-connection=attached' not in native:
        errors.append('Native launcher must not discover wireless devices')
    scheme_path = app / 'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme'
    scheme = scheme_path.read_text()
    for action_name in ('TestAction', 'LaunchAction', 'ProfileAction'):
        action = re.search(rf'<{action_name}\b[^>]*>(.*?)</{action_name}\s*>', scheme, re.S)
        arguments = [] if action is None else re.findall(
            r'<CommandLineArgument\b([^>]*)/>', action.group(1)
        )
        if not any(
            re.search(r"\bargument\s*=\s*(['\"])--disable-vm-service-publication\1", argument)
            and re.search(r"\bisEnabled\s*=\s*(['\"])YES\1", argument)
            for argument in arguments
        ):
            errors.append(
                f'iOS {action_name}: direct Xcode launches must disable VM service publication'
            )
    # The demo and the framework packages it composes must not grow another
    # socket/discovery path behind the checked HTTP/WebSocket client.
    scopes = [app / 'lib'] + [root / 'client' / p / 'lib' for p in (
        'zen_core', 'zen_transport', 'zen_identity', 'zen_secure_store',
        'zen_ui_identity', 'zen_ui_navigation', 'zen_ui_widgets')]
    primitive = re.compile(r'\b(?:Socket\.(?:connect|startConnect)|(?:RawDatagramSocket|RawSocket|'
                           r'RawSecureSocket|SecureSocket|ServerSocket|HttpServer)\.\w+|NetworkInterface\.list|'
                           r'InternetAddress\.lookup|HttpOverrides\.(?:global|runZoned|runWithHttpOverrides))\b')
    for scope in scopes:
        files = list(scope.rglob('*.dart'))
        if not files:
            errors.append(f'{scope}: empty audit scope')
        for path in files:
            if path == app / 'lib/src/backend_network_io.dart':
                continue  # The implementation of the boundary; covered by real socket tests.
            source = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
            if primitive.search(source):
                errors.append(f'{path}: unreviewed raw socket or discovery API')
    inventory = app / '.flutter-plugins-dependencies'
    if inventory.exists():
        errors += check_plugins(json.loads(inventory.read_text()))
    return errors


def check_bundle(app, mode):
    errors = check_plist(plistlib.loads((app / 'Contents/Info.plist').read_bytes()), str(app))
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)],
                            capture_output=True, check=True)
    errors += check_entitlements(plistlib.loads(result.stdout), str(app), mode != 'release')
    if mode == 'profile' and 'com.apple.security.cs.allow-jit' in plistlib.loads(result.stdout):
        errors.append(f'{app}: AOT profile must not request JIT')
    # Inspect every embedded privacy manifest, including plugin resources.
    for path in app.rglob('PrivacyInfo.xcprivacy'):
        data = plistlib.loads(path.read_bytes())
        if data.get('NSPrivacyTracking') or data.get('NSPrivacyTrackingDomains') or data.get('NSPrivacyCollectedDataTypes'):
            errors.append(f'{path}: unreviewed tracking or collected-data declaration')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, help='Also inspect a built macOS .app')
    parser.add_argument('--mode', choices=('debug', 'profile', 'release'))
    args = parser.parse_args()
    if args.app and not args.mode:
        parser.error('--app requires --mode')
    root = Path(__file__).resolve().parents[1]
    try:
        errors = check(root)
        if args.app:
            inventory = root / DEMO / '.flutter-plugins-dependencies'
            errors += check_plugins(json.loads(inventory.read_text()))
            errors += check_bundle(args.app, args.mode)
    except (OSError, ValueError, KeyError, IndexError, plistlib.InvalidFileException,
            subprocess.CalledProcessError) as error:
        errors = [f'Cannot verify demo network policy: {error}']
    for error in errors:
        print(error)
    if not errors:
        print('Demo network configuration checks passed')
    return int(bool(errors))


if __name__ == '__main__':
    raise SystemExit(main())
