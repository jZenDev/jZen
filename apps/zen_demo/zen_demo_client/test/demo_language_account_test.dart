import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_demo_client/src/app.dart';
import 'package:zen_demo_client/src/providers.dart';
import 'package:zen_demo_client/src/screens/demo_language_menu.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// What the language picker owes the server: `users.language` decides the language of e-mail, so
/// a signed-in choice must reach it - after the device has applied and stored it, and without the
/// device ever depending on the answer.

// The sentences are literals on purpose: they are what the person reads, in the language chosen.
const _accountEn =
    'Your language was changed, but it could not be saved to your account. Emails may still '
    'arrive in the previous language. Choose the language again to retry.';
const _accountUk =
    'Мову змінено, але не вдалося зберегти її в обліковому записі. Листи можуть і далі '
    'надходити попередньою мовою. Щоб спробувати ще раз, виберіть мову знову.';
const _deviceUk =
    'Мову змінено, але не вдалося зберегти її на цьому пристрої. Після перезапуску застосунку '
    'цей вибір буде втрачено.';

const _signedIn = IdentityContract(
  id: 'person-1',
  lifecycle: IdentityLifecycleContract(state: 'active'),
  authority: AuthorityContract(),
  createdAt: 0,
  emailVerified: true,
);

const _otherPerson = IdentityContract(
  id: 'person-2',
  lifecycle: IdentityLifecycleContract(state: 'active'),
  authority: AuthorityContract(),
  createdAt: 0,
  emailVerified: true,
);

/// What the device held at the moment the server was told.
typedef _Call = ({String tag, Locale applied, String? stored});

final class _FakeIdentityRepository implements IdentityRepository {
  _FakeIdentityRepository({this.identity = _signedIn});

  final IdentityContract? identity;
  final List<_Call> calls = [];

  /// Answers one call; by default the server accepts.
  Future<ZenResult<void>> Function(String tag) answer = (_) async => const ZenResult.ok(null);

  late ProviderContainer container;
  late ZenLocaleStore store;

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => ZenResult.ok(identity);

  @override
  Future<ZenResult<void>> setLanguage(String language) {
    calls.add((tag: language, applied: container.read(localeProvider), stored: store.read()));
    return answer(language);
  }

  @override
  Future<ZenResult<void>> logout() async => const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.ok(_otherPerson);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A device that cannot write the tags in [failing].
final class _FailingLocaleStore implements ZenLocaleStore {
  _FailingLocaleStore([this.failing = const {'en', 'uk'}]);

  final Set<String> failing;
  String? _tag;

  @override
  String? read() => _tag;

  @override
  Future<void> write(String tag) async {
    if (failing.contains(tag)) throw StateError('disk full');
    _tag = tag;
  }
}

final class _RecordingLogger implements ZenLogger {
  final List<({String message, Object? error})> errors = [];
  final List<String> warnings = [];

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? internalData,
  }) => errors.add((message: message, error: error));

  @override
  void debug(String message, {Map<String, dynamic>? internalData}) {}

  @override
  void info(String message, {Map<String, dynamic>? internalData}) {}

  @override
  void warn(String message, {Map<String, dynamic>? internalData}) => warnings.add(message);
}

const _refused = ZenResult<void>.err(ZenValidationError('unsupported_language'));

void main() {
  late _RecordingLogger logger;

  setUp(() {
    final previous = ZenLogger.instance;
    ZenLogger.instance = logger = _RecordingLogger();
    addTearDown(() => ZenLogger.instance = previous);
  });

  ProviderContainer containerFor(_FakeIdentityRepository repository, {ZenLocaleStore? store}) {
    repository.store = store ?? ZenMemoryLocaleStore();
    final container = ProviderContainer(
      overrides: [
        deviceLanguagesProvider.overrideWithValue(const ['en-US']),
        localePreferenceProvider.overrideWithValue(
          ZenLocalePreference(supported: demoSupportedLocales, store: repository.store),
        ),
        identityRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    return repository.container = container;
  }

  /// The real app, signed in, on the dashboard where the picker lives.
  Future<ProviderContainer> launch(
    WidgetTester tester,
    _FakeIdentityRepository repository, {
    ZenLocaleStore? store,
  }) async {
    final container = containerFor(repository, store: store);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DemoApp()),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> choose(WidgetTester tester, String endonym) async {
    await tester.tap(
      find.descendant(of: find.byType(DemoLanguageMenu), matching: find.byType(ZenIconButton)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(endonym));
    await tester.pumpAndSettle();
  }

  /// Lets a message expire, so its timer does not outlive the test.
  Future<void> expireMessage(WidgetTester tester) async {
    await tester.pump(zenMessageDuration * 3);
    await tester.pumpAndSettle();
  }

  testWidgets('signed in, a choice is sent once, after the device applied and stored it', (
    tester,
  ) async {
    final repository = _FakeIdentityRepository();
    await launch(tester, repository);

    await choose(tester, 'Українська');

    expect(repository.calls, [(tag: 'uk', applied: const Locale('uk'), stored: 'uk')]);
    expect(find.text(_accountUk), findsNothing);
    expect(logger.errors, isEmpty);
  });

  testWidgets('with no session the server is not called', (tester) async {
    final repository = _FakeIdentityRepository(identity: null);
    final container = containerFor(repository);
    expect(await container.read(identitySessionStoreProvider.future), isNull);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: [zenWidgetsLocaleDelegate],
          home: Scaffold(body: DemoLanguageMenu(label: 'Language')),
        ),
      ),
    );

    await choose(tester, 'Українська');

    expect(container.read(localeProvider), const Locale('uk'));
    expect(repository.store.read(), 'uk');
    expect(repository.calls, isEmpty);
  });

  testWidgets('the device does not wait for the server', (tester) async {
    final answer = Completer<ZenResult<void>>();
    final repository = _FakeIdentityRepository()..answer = (_) => answer.future;
    await launch(tester, repository);

    await choose(tester, 'Українська');

    expect(find.text('Головна'), findsWidgets);
    expect(repository.store.read(), 'uk');
    answer.complete(const ZenResult.ok(null));
    await tester.pumpAndSettle();
  });

  for (final (name, answer) in <(String, Future<ZenResult<void>> Function(String))>[
    ('refused', (_) async => _refused),
    ('throwing', (_) async => throw Exception('connection refused')),
  ]) {
    testWidgets('a $name call keeps the chosen language, says so in it and is logged', (
      tester,
    ) async {
      final repository = _FakeIdentityRepository()..answer = answer;
      final container = await launch(tester, repository);

      await choose(tester, 'Українська');

      expect(container.read(localeProvider), const Locale('uk'));
      expect(repository.store.read(), 'uk');
      expect(find.text(_accountUk), findsOneWidget);
      expect(logger.errors, hasLength(1));
      expect(logger.errors.single.error, isNotNull);
      await expireMessage(tester);
    });
  }

  testWidgets('a second failure is reported again', (tester) async {
    final repository = _FakeIdentityRepository()..answer = (_) async => _refused;
    await launch(tester, repository);

    await choose(tester, 'Українська');
    await expireMessage(tester);
    expect(find.text(_accountUk), findsNothing);
    await choose(tester, 'English');

    expect(find.text(_accountEn), findsOneWidget);
    await expireMessage(tester);
  });

  testWidgets('a failure is still reported after the picker has left the screen', (tester) async {
    final answer = Completer<ZenResult<void>>();
    final repository = _FakeIdentityRepository()..answer = (_) => answer.future;
    await launch(tester, repository);
    await choose(tester, 'Українська');

    await tester.tap(find.text('Вітрина').last);
    await tester.pumpAndSettle();
    expect(find.byType(DemoLanguageMenu), findsNothing);
    answer.complete(_refused);
    await tester.pumpAndSettle();

    expect(find.text(_accountUk), findsOneWidget);
    await expireMessage(tester);
  });

  testWidgets('quick choices reach the server in order and only the last one is reported', (
    tester,
  ) async {
    final answers = <Completer<ZenResult<void>>>[];
    final repository = _FakeIdentityRepository()
      ..answer = (_) => (answers..add(Completer<ZenResult<void>>())).last.future;
    final container = await launch(tester, repository);

    await choose(tester, 'Українська');
    await choose(tester, 'English');
    // The second waits for the first: sent side by side they could land in either order and
    // leave the account in the language the person moved away from.
    expect(repository.calls.map((c) => c.tag), ['uk']);
    // Only the request waits; the device does not.
    expect(container.read(localeProvider), const Locale('en'));
    expect(repository.store.read(), 'en');

    answers[0].complete(_refused);
    await tester.pumpAndSettle();
    expect(repository.calls.map((c) => c.tag), ['uk', 'en']);
    expect(find.text(_accountEn), findsNothing, reason: 'a newer choice is still on its way');

    answers[1].complete(const ZenResult.ok(null));
    await tester.pumpAndSettle();
    expect(find.text(_accountEn), findsNothing);
    expect(logger.errors, hasLength(1), reason: 'logged even when not shown');
  });

  testWidgets('a failed device write keeps the language, says so, and sends nothing', (
    tester,
  ) async {
    final repository = _FakeIdentityRepository();
    final container = await launch(tester, repository, store: _FailingLocaleStore());

    await choose(tester, 'Українська');

    expect(container.read(localeProvider), const Locale('uk'));
    expect(find.text(_deviceUk), findsOneWidget);
    expect(repository.calls, isEmpty);
    expect(logger.errors, hasLength(1));
    expect(logger.errors.single.error, isStateError);
    await expireMessage(tester);
  });

  /// Answers that arrive only when the test says so.
  (_FakeIdentityRepository, List<Completer<ZenResult<void>>>) heldRepository() {
    final answers = <Completer<ZenResult<void>>>[];
    final repository = _FakeIdentityRepository()
      ..answer = (_) => (answers..add(Completer<ZenResult<void>>())).last.future;
    return (repository, answers);
  }

  testWidgets('a call that is never answered is reported and does not hold up the next', (
    tester,
  ) async {
    final (repository, answers) = heldRepository();
    await launch(tester, repository);

    await choose(tester, 'Українська');
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(find.text(_accountUk), findsOneWidget);
    expect(logger.errors.single.error, isA<TimeoutException>());
    await expireMessage(tester);

    await choose(tester, 'English');
    expect(repository.calls.map((c) => c.tag), ['uk', 'en']);
    answers[1].complete(const ZenResult.ok(null));
    await tester.pumpAndSettle();
  });

  testWidgets('a refusal is still shown when the newer choice never reached the server', (
    tester,
  ) async {
    final (repository, answers) = heldRepository();
    await launch(tester, repository, store: _FailingLocaleStore(const {'en'}));

    await choose(tester, 'Українська');
    await choose(tester, 'English');
    await expireMessage(tester);
    answers.single.complete(_refused);
    await tester.pumpAndSettle();

    // The chosen language is English, so that is the language it is said in.
    expect(find.text(_accountEn), findsOneWidget);
    await expireMessage(tester);
  });

  testWidgets('a failed device write between two choices does not let them overtake', (
    tester,
  ) async {
    final (repository, answers) = heldRepository();
    await launch(tester, repository, store: _FailingLocaleStore(const {'en'}));

    await choose(tester, 'Українська');
    await choose(tester, 'English');
    await expireMessage(tester);
    await choose(tester, 'Українська');
    expect(repository.calls, hasLength(1));

    answers[0].complete(const ZenResult.ok(null));
    await tester.pumpAndSettle();
    expect(repository.calls.map((c) => c.tag), ['uk', 'uk']);
    answers[1].complete(const ZenResult.ok(null));
    await tester.pumpAndSettle();
  });

  testWidgets('a waiting choice is not sent to whoever signs in next', (tester) async {
    final (repository, answers) = heldRepository();
    final container = await launch(tester, repository);
    await choose(tester, 'Українська');
    await choose(tester, 'English');

    final session = container.read(identitySessionStoreProvider.notifier);
    await session.logout();
    await session.login('other@example.com', 'unused-by-the-fake');
    await tester.pumpAndSettle();
    answers.single.complete(const ZenResult.ok(null));
    await tester.pumpAndSettle();

    expect(repository.calls.map((c) => c.tag), ['uk']);
    expect(logger.warnings, hasLength(1), reason: 'dropped, and said so in the log');
  });

  testWidgets('an answer arriving after the app is gone is logged and nothing throws', (
    tester,
  ) async {
    final (repository, answers) = heldRepository();
    final container = await launch(tester, repository);
    await choose(tester, 'Українська');

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    answers.single.complete(_refused);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(logger.errors, hasLength(1));
  });
}
