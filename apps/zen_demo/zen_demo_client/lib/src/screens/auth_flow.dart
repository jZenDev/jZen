import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

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
