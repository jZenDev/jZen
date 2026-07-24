import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import '../l10n/generated/demo_localizations.dart';

/// The unauthenticated flow: login, register, and restore-password, composed from the reused
/// zen_ui_identity screens. On success the identity session store flips and the app root swaps
/// to the authenticated shell, so this widget just switches between the three screens in place
/// (no route pushing) to keep a single, predictable navigator.
enum _AuthScreen { login, register, restore }

class AuthFlow extends ConsumerStatefulWidget {
  const AuthFlow({super.key});

  @override
  ConsumerState<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends ConsumerState<AuthFlow> {
  _AuthScreen _screen = _AuthScreen.login;

  void _go(_AuthScreen screen) => setState(() => _screen = screen);

  @override
  Widget build(BuildContext context) => switch (_screen) {
    // The screens take no wording: each reads IdentityLocalizations off the context, so the
    // app supplies only the delegate and the chosen locale (ADR-009).
    _AuthScreen.login => LoginScreen(
      onRegisterClick: () => _go(_AuthScreen.register),
      onForgotPasswordClick: () => _go(_AuthScreen.restore),
      // The demo has no shared/seed account, so the login page says so on itself rather than
      // leaving it to the README. The wording is the app's (a DemoLocalizations string), the
      // slot is the framework's.
      banner: _DemoLoginHint(),
    ),
    _AuthScreen.register => RegisterScreen(
      onLoginClick: () => _go(_AuthScreen.login),
    ),
    _AuthScreen.restore => RestorePasswordScreen(
      onBackClick: () => _go(_AuthScreen.login),
      onRestoreSuccess: () => _go(_AuthScreen.login),
    ),
  };
}

/// The demo's on-screen "how to sign in" hint, shown in the framework login screen's banner slot.
class _DemoLoginHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              DemoLocalizations.of(context).demoLoginHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
