import 'package:zen_core/zen_core.dart';
import 'package:zen_localization/zen_localization.dart';

/// Access to localized messages for the Identity UI package.
///
/// Wraps [ZenLocalizationService] to provide strongly-typed or constant-key access
/// to messages without exposing raw strings in the UI.
class IdentityMessages {
  /// The localization service.
  final ZenLocalizationService _service;

  /// The current language code.
  final String _language;

  /// Creates an [IdentityMessages] wrapper.
  const IdentityMessages(this._service, this._language);

  /// Helper to get the module name.
  static const String module = 'identity';

  String _t(String key, [Map<String, dynamic> params = const {}]) {
    return _service.translate(
      key,
      language: _language,
      module: module,
      params: params,
    );
  }

  String get loginTitle => _t('login.title');
  String get registerTitle => _t('register.title');
  String get restorePasswordTitle => _t('restore.password.title');

  String get emailLabel => _t('email.label');
  String get passwordLabel => _t('password.label');
  String get confirmPasswordLabel => _t('confirm.password.label');

  String get loginButton => _t('login.button');
  String get registerButton => _t('register.button');
  String get sendResetLinkButton => _t('send.reset.link.button');
  String get logoutButton => _t('logout.button');

  String get profileTitle => _t('profile.title');
  String get rolesTitle => _t('roles.title');
  String get rolesLabel => _t('roles.label');
  String get profileAvatarLabel => _t('profile.avatar.label');
  String get backButtonTooltip => _t('back.button.tooltip');

  String get restorePasswordInfo => _t('restore.password.info');
  String get resetLinkSentSuccess => _t('reset.link.sent.success');
  String get alreadyHaveAccount => _t('already.have.account');
  String get notAuthenticated => _t('not.authenticated');

  String get unknownError => _t('unknown.error');

  String get validationRequired => _t('validation.required');
  String get validationEmail => _t('validation.email');
  String get validationPasswordMismatch => _t('validation.password.mismatch');

  String error(ZenError error) {
    if (error is ZenUnauthorizedError) {
      return _t('error.unauthorized');
    }
    if (error is ZenNotFoundError) {
      return _t('error.not_found');
    }
    if (error is ZenValidationError) {
      return _t('error.validation');
    }
    if (error is ZenConflictError) {
      return _t('error.conflict');
    }
    return error.message;
  }
}
