/// UI identity flows and components for jZen.
///
/// ## Localization
///
/// Every screen in this package reads its wording from the typed, generated
/// [IdentityLocalizations], resolved from the [BuildContext] - so a consuming app supplies no
/// strings, only the delegate:
///
/// ```dart
/// MaterialApp(
///   localizationsDelegates: const [
///     identityLocaleDelegate,          // not IdentityLocalizations.delegate - see below
///     GlobalMaterialLocalizations.delegate,
///     GlobalCupertinoLocalizations.delegate,
///     GlobalWidgetsLocalizations.delegate,
///   ],
///   supportedLocales: [for (final tag in myAppLocales) Locale(tag)],
/// )
/// ```
///
/// [identityLocaleDelegate] rather than the generated `IdentityLocalizations.delegate`: the
/// supported set is the application's, not jZen's (ADR-044), and the generated delegate refuses
/// any locale this package has no ARB for - which leaves `IdentityLocalizations.of(context)` null
/// and throws on the first string read. The degrading delegate falls back to English instead. To
/// render these strings in a language jZen does not ship, subclass `IdentityLocalizationsEn`,
/// wrap it in your own delegate, and list that delegate *first*.
///
/// Changing `MaterialApp.locale` re-renders the flows in the new language; see
/// `IdentityErrorText.errorText` for the localized wording of a [ZenError].
library;

// L10n
export 'src/l10n/generated/identity_localizations.dart';
// The per-locale implementations, exported so an application can translate this package's
// strings itself (ADR-044): subclass the fallback one and override only the getters it wants
// rendered in a locale jZen ships nothing for, rather than reimplementing every string.
export 'src/l10n/generated/identity_localizations_en.dart';
export 'src/l10n/generated/identity_localizations_uk.dart';
export 'src/l10n/identity_locale_delegate.dart';
export 'src/l10n/identity_error_text.dart';
// Screens
export 'src/screens/authority_roles_screen.dart';
export 'src/screens/login_screen.dart';
export 'src/screens/profile_screen.dart';
export 'src/screens/register_screen.dart';
export 'src/screens/restore_password_screen.dart';
export 'src/screens/set_password_screen.dart';
// State
export 'src/state/identity_repository.dart';
export 'src/state/auth_link_outcome.dart';
export 'src/state/identity_session_store.dart';
export 'src/state/session_client_provider.dart';
// Theme
export 'src/theme/identity_theme_extension.dart';
// Widgets
export 'src/widgets/identity_button.dart';
export 'src/widgets/identity_status_chip.dart';
export 'src/widgets/identity_text_field.dart';
export 'src/widgets/zen_auth_link_listener.dart';
