import 'package:zen_localization/zen_localization.dart';

/// Typed messages accessor for the 'navigation' module.
///
/// Wraps [ZenLocalizationService] to provide strongly-typed access
/// to navigation keys without exposing raw strings.
class NavigationMessages {
  /// Creates a [NavigationMessages] wrapper.
  const NavigationMessages(this._service, this._language);

  final ZenLocalizationService _service;
  final String _language;

  /// The label for the "More" button (navigation.more).
  String get more => _t('navigation.more');

  /// Helper to reduce boilerplate.
  String _t(String key) => _service.translate(
        key,
        language: _language,
        module: 'navigation',
      );
}
