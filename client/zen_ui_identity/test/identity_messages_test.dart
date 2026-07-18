import 'package:zen_core/zen_core.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:zen_ui_identity/src/l10n/identity_messages.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocalization implements ZenLocalizationService {
  final Map<String, String> _map;
  _FakeLocalization(this._map);

  Map<String, String> getGlobal(String language) => _map;

  Map<String, String> getModule(String module, String language) => _map;

  @override
  String translate(
    String key, {
    required String language,
    String? module,
    Map<String, dynamic> params = const {},
  }) => _map[key] ?? key;

  // unused in tests
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('identity messages getters delegate to localization service', () {
    final data = {
      'login.title': 'Login',
      'register.title': 'Register',
      'error.unauthorized': 'Unauthorized',
      'error.not_found': 'Not found',
      'error.validation': 'Validation failed',
      'error.conflict': 'Conflict',
      'validation.required': 'Required',
      'validation.email': 'Bad email',
      'validation.password.mismatch': 'Mismatch',
    };

    final svc = _FakeLocalization(data);
    final msgs = IdentityMessages(svc, 'en');

    expect(msgs.loginTitle, 'Login');
    expect(msgs.registerTitle, 'Register');
    expect(msgs.validationRequired, 'Required');
    expect(msgs.validationEmail, 'Bad email');

    // Error mapping
    expect(msgs.error(const ZenUnauthorizedError('x')), 'Unauthorized');
    expect(msgs.error(const ZenNotFoundError('x')), 'Not found');
    expect(msgs.error(const ZenValidationError('x')), 'Validation failed');
    expect(msgs.error(const ZenConflictError('x')), 'Conflict');

    // unknown error returns message
    const unknown = ZenUnknownError('boom');
    expect(msgs.error(unknown), 'boom');
  });

  test('passes module and language to localization service', () {
    String? calledModule;
    String? calledLanguage;
    String? calledKey;

    // override translate to capture parameters
    final capturing = _CapturingLocalization((
      key, {
      required String language,
      String? module,
      Map<String, dynamic> params = const {},
    }) {
      calledKey = key;
      calledModule = module;
      calledLanguage = language;
      return 'x';
    });

    final msgs = IdentityMessages(capturing, 'ru');
    // call some getters
    expect(msgs.loginTitle, 'x');
    expect(calledKey, 'login.title');
    expect(calledModule, IdentityMessages.module);
    expect(calledLanguage, 'ru');
  });
}

class _CapturingLocalization implements ZenLocalizationService {
  final String Function(
    String, {
    required String language,
    String? module,
    Map<String, dynamic> params,
  })
  _cb;
  _CapturingLocalization(this._cb);
  @override
  String translate(
    String key, {
    required String language,
    String? module,
    Map<String, dynamic> params = const {},
  }) => _cb(key, language: language, module: module, params: params);
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
