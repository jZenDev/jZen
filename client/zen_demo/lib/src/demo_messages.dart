import 'package:zen_localization/zen_localization.dart';

/// Typed access to the demo's own localized strings, mirroring DartZen's
/// ../DartZen/apps/ZenDemo/dartzen_demo_client/lib/src/l10n/client_messages.dart (ClientMessages).
///
/// Keys live in the merged global bundles assets/l10n/{en,uk}.json (production-mode
/// localization: a single merged file per language, graceful key fallback). The identity and
/// navigation packages read their own keys from the same bundle.
class DemoMessages {
  const DemoMessages(this._service, this._language);

  final ZenLocalizationService _service;
  final String _language;

  String _t(String key, [Map<String, dynamic> params = const {}]) =>
      _service.translate(key, language: _language, params: params);

  String get appTitle => _t('demo.app.title');
  String get welcomeTitle => _t('demo.welcome.title');
  String get welcomeSubtitle => _t('demo.welcome.subtitle');

  String get navHome => _t('demo.nav.home');
  String get navTerms => _t('demo.nav.terms');
  String get navProfile => _t('demo.nav.profile');
  String get languageLabel => _t('demo.language.label');

  String get pingSection => _t('demo.ping.section');
  String get pingJson => _t('demo.ping.json');
  String get pingProtobuf => _t('demo.ping.protobuf');
  String pingResult(String mode, String message) =>
      _t('demo.ping.result', {'mode': mode, 'message': message});
  String pingError(String error) => _t('demo.ping.error', {'error': error});

  String get wsSection => _t('demo.ws.section');
  String get wsConnect => _t('demo.ws.connect');
  String get wsDisconnect => _t('demo.ws.disconnect');
  String get wsSend => _t('demo.ws.send');
  String wsStatus(String status) => _t('demo.ws.status', {'status': status});
  String wsReceived(String message) => _t('demo.ws.received', {'message': message});

  String get termsTitle => _t('demo.terms.title');
  String get termsLoading => _t('demo.terms.loading');
  String termsError(String error) => _t('demo.terms.error', {'error': error});

  String get profileLoading => _t('demo.profile.loading');
  String profileError(String error) => _t('demo.profile.error', {'error': error});
  String get profileBio => _t('demo.profile.bio');
}
