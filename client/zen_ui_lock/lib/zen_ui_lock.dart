/// jZen UI Lock - an optional PIN lock for a jZen application that has no sign-in.
///
/// - [ZenPinLock]: whether a PIN is set and whether the app is locked; wrong-attempt shut-out
/// - [ZenLockGate]: covers the app while locked, and in the app switcher
/// - [ZenPinLockSwitch], [showZenPinSetup], [showZenPinOff]: turning it on, changing it, off
/// - [lockLocaleDelegate]: this package's strings, for `MaterialApp.localizationsDelegates`
///
/// See docs/architecture/DECISIONS.md ADR-065.
library;

export 'src/l10n/generated/lock_localizations.dart';
export 'src/l10n/lock_locale_delegate.dart';
export 'src/screens/show_zen_pin_screens.dart';
export 'src/screens/zen_pin_off_screen.dart';
export 'src/screens/zen_pin_setup_screen.dart';
export 'src/screens/zen_unlock_screen.dart';
export 'src/state/zen_lock_storage.dart';
export 'src/state/zen_owner_check.dart';
export 'src/state/zen_pin_hash.dart' show zenPinIterations;
export 'src/state/zen_pin_lock.dart';
export 'src/state/zen_pin_locked_out_error.dart';
export 'src/widgets/zen_lock_gate.dart';
export 'src/widgets/zen_pin_lock_switch.dart';
