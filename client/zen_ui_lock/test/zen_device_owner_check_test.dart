import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

/// Answers `isDeviceSupported` as told; anything else is a test mistake.
final class _FakeAuth implements LocalAuthentication {
  Object? throws;
  bool supported = true;
  int asked = 0;

  @override
  Future<bool> isDeviceSupported() async {
    asked++;
    if (throws case final error?) throw error;
    return supported;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

/// The real [ZenDeviceOwnerCheck] decides which recovery a device gets, so its branches are tested
/// directly, not through a fake owner check.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Linux has no owner check, and local_auth is not even asked', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final auth = _FakeAuth();

    final result = await ZenDeviceOwnerCheck(auth: auth).isAvailable();

    expect(result.dataOrNull, isFalse);
    expect(auth.asked, 0);
  });

  test('a device with no passcode or Windows Hello has no owner check', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final auth = _FakeAuth()..supported = false;

    expect((await ZenDeviceOwnerCheck(auth: auth).isAvailable()).dataOrNull, isFalse);
  });

  test('a device that supports it has an owner check', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect((await ZenDeviceOwnerCheck(auth: _FakeAuth()).isAvailable()).dataOrNull, isTrue);
  });

  test('a platform with no plugin has no owner check', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final auth = _FakeAuth()..throws = MissingPluginException('local_auth');

    expect((await ZenDeviceOwnerCheck(auth: auth).isAvailable()).dataOrNull, isFalse);
  });

  test(
    'any other failure is an error — never "no owner check", which would offer erasing',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final auth = _FakeAuth()..throws = PlatformException(code: 'busy');

      final result = await ZenDeviceOwnerCheck(auth: auth).isAvailable();

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isA<ZenUnknownError>());
    },
  );
}
