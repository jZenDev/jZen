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
///   localizationsDelegates: IdentityLocalizations.localizationsDelegates,
///   supportedLocales: IdentityLocalizations.supportedLocales,
/// )
/// ```
///
/// Changing `MaterialApp.locale` re-renders the flows in the new language; see
/// `IdentityErrorText.errorText` for the localized wording of a [ZenError].
library;

// L10n
export 'src/l10n/generated/identity_localizations.dart';
export 'src/l10n/identity_error_text.dart';
// Screens
export 'src/screens/authority_roles_screen.dart';
export 'src/screens/login_screen.dart';
export 'src/screens/profile_screen.dart';
export 'src/screens/register_screen.dart';
export 'src/screens/restore_password_screen.dart';
// State
export 'src/state/identity_repository.dart';
export 'src/state/identity_session_store.dart';
// Theme
export 'src/theme/identity_theme_extension.dart';
// Widgets
export 'src/widgets/identity_button.dart';
export 'src/widgets/identity_status_chip.dart';
export 'src/widgets/identity_text_field.dart';
