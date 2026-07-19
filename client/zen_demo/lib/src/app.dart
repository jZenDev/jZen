import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'demo_messages.dart';
import 'providers.dart';
import 'screens/auth_flow.dart';
import 'screens/home_shell.dart';

/// The root of zen_demo. Boots localization (a spinner until the merged bundles load), then
/// routes on the identity session: anonymous -> the auth flow, authenticated -> the home shell.
/// This is the state-based routing DartZen's ZenDemoApp used, rebuilt on Riverpod so the reused
/// zen_ui_identity/navigation packages drive the same session the SupabaseIdentityRepository holds.
class DemoApp extends ConsumerWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localization = ref.watch(localizationServiceProvider);

    return MaterialApp(
      title: 'jZen Demo',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: localization.when(
        loading: () => const _Splash(),
        error: (error, _) => _ErrorScreen(message: '$error'),
        data: (service) => _Root(service: service),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      extensions: [
        IdentityThemeExtension(
          successColor: Colors.green,
          errorColor: scheme.error,
          warningColor: Colors.orange,
          brandColor: scheme.primary,
          surfaceColor: scheme.surface,
          titleStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          subtitleStyle: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root({required this.service});

  final ZenLocalizationService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final session = ref.watch(identitySessionStoreProvider);
    final identityMessages = IdentityMessages(service, language);
    final demoMessages = DemoMessages(service, language);

    return session.when(
      loading: () => const _Splash(),
      error: (_, _) => AuthFlow(messages: identityMessages),
      data: (identity) => identity == null
          ? AuthFlow(messages: identityMessages)
          : HomeShell(
              localization: service,
              demoMessages: demoMessages,
              identityMessages: identityMessages,
            ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(message)));
}
