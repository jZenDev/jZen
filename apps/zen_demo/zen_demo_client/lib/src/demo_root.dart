import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'demo_splash.dart';
import 'screens/auth_flow.dart';
import 'screens/home_shell.dart';

/// Routes on the identity session: anonymous -> the auth flow, authenticated -> the home shell.
class DemoRoot extends ConsumerWidget {
  const DemoRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(identitySessionStoreProvider);

    return session.when(
      loading: () => const DemoSplash(),
      error: (_, _) => const AuthFlow(),
      data: (identity) {
        if (identity == null) return const AuthFlow();
        // Signed in, but a password-recovery link is only finished once a new password exists —
        // so that gate comes before the app. It is a framework-supplied condition and screen; the
        // app decides only where in its routing they belong, which is here, ahead of everything.
        if (ref.watch(passwordResetRequiredProvider)) return const SetPasswordScreen();
        return const HomeShell();
      },
    );
  }
}
