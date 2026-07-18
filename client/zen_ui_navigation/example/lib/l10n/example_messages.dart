import 'package:zen_localization/zen_localization.dart';

/// Typed messages accessor for the 'example' module.
class ExampleMessages {
  /// Creates a [ExampleMessages] wrapper.
  const ExampleMessages(this._service, this._language);

  final ZenLocalizationService _service;
  final String _language;

  // Home Screen
  String get homeTitle => _t('home.title');
  String get homeWelcome => _t('home.welcome');
  String get homeDescription => _t('home.description');
  String get homeFeaturesTitle => _t('home.features.title');
  String get homeFeaturesAdaptive => _t('home.features.adaptive');
  String get homeFeaturesHighlights => _t('home.features.highlights');
  String get homeFeaturesOverflow => _t('home.features.overflow');
  String get homeFeaturesBadges => _t('home.features.badges');
  String get homeFeaturesRiverpod => _t('home.features.riverpod');

  // Settings Screen
  String get settingsTitle => _t('settings.title');
  String get settingsAppearanceTitle => _t('settings.appearance.title');
  String get settingsAppearanceDarkMode => _t('settings.appearance.darkMode');
  String get settingsAppearanceDarkModeSubtitle =>
      _t('settings.appearance.darkModeSubtitle');
  String get settingsAppearanceTextSize => _t('settings.appearance.textSize');
  String get settingsNotificationsTitle => _t('settings.notifications.title');
  String get settingsNotificationsPush => _t('settings.notifications.push');
  String get settingsNotificationsReceive =>
      _t('settings.notifications.receive');
  String get settingsNavigationTitle => _t('settings.navigation.title');
  String get settingsNavigationType => _t('settings.navigation.type');
  String get settingsNavigationAdaptive => _t('settings.navigation.adaptive');
  String get settingsAboutTitle => _t('settings.about.title');
  String get settingsAboutVersion => _t('settings.about.version');
  String get settingsAboutPackage => _t('settings.about.package');
  String get settingsAboutPackageValue => _t('settings.about.packageValue');

  // Profile Screen
  String get profileTitle => _t('profile.title');
  String get profileEditClicked => _t('profile.editClicked');
  String get profileBadgeCount => _t('profile.badgeCount');
  String get profileBadgeSubtitle => _t('profile.badgeSubtitle');
  String get profileLocation => _t('profile.location');
  String get profileLocationValue => _t('profile.locationValue');
  String get profileMemberSince => _t('profile.memberSince');
  String get profileMemberSinceValue => _t('profile.memberSinceValue');
  String get profileNotifications => _t('profile.notifications');
  String get profilePrivacy => _t('profile.privacy');
  String get profileHelpSupport => _t('profile.helpSupport');

  // Search Screen
  String get searchTitle => _t('search.title');
  String get searchHint => _t('search.hint');
  String get searchSelected => _t('search.selected');

  /// Helper to reduce boilerplate.
  String _t(String key) => _service.translate(
    key,
    language: _language,
    module: 'example', // We'll treat the app as 'example' module
  );
}
