import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'support/lock_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zen_ui_lock/screen');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <bool>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setSecure');
      calls.add((call.arguments as Map<Object?, Object?>)['secure']! as bool);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('a gate that asks sets the flag while mounted and clears it after', (tester) async {
    final lock = await memoryLock();
    await tester.pumpWidget(lockedApp(lock: lock, secureScreen: true));
    expect(calls, [true]);

    await tester.pumpWidget(const SizedBox());
    expect(calls, [true, false]);
  });

  testWidgets('a gate that does not ask never touches the window', (tester) async {
    final lock = await memoryLock();
    await tester.pumpWidget(lockedApp(lock: lock));
    await tester.pumpWidget(const SizedBox());
    expect(calls, isEmpty);
  });

  testWidgets('turning the option on or off follows it', (tester) async {
    final lock = await memoryLock();
    await tester.pumpWidget(lockedApp(lock: lock));
    await tester.pumpWidget(lockedApp(lock: lock, secureScreen: true));
    await tester.pumpWidget(lockedApp(lock: lock));
    expect(calls, [true, false]);
  });

  test('a platform without the plugin is "not applicable", not an error', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await ZenScreenSecurity.setSecure(true), isFalse);
  });

  test('a failure on a platform that has it is thrown', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'no_activity');
    });
    await expectLater(ZenScreenSecurity.setSecure(true), throwsA(isA<PlatformException>()));
  });
}
