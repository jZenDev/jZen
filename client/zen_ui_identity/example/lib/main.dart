import 'dart:async';

import 'package:zen_identity/zen_identity.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Locally define the localization service provider for example since it's not exported
final myLocalizationServiceProvider = Provider<ZenLocalizationService>((ref) {
  return ZenLocalizationService(
    config: const ZenLocalizationConfig(
      isProduction: false,
      globalPath: 'assets/l10n',
    ),
  );
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ProviderScope(
      overrides: [
        // The Supabase re-point (TA-5): the UI depends only on the IdentityRepository
        // interface, so wiring the real repository is a one-line provider override. It
        // targets the compile-time ZEN_API_URL and talks to the zen-identity endpoints.
        identityRepositoryProvider.overrideWith(
          (ref) => SupabaseIdentityRepository(),
        ),
      ],
      child: const ExampleApp(),
    ),
  );
}

class ExampleApp extends ConsumerStatefulWidget {
  const ExampleApp({super.key});

  @override
  ConsumerState<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends ConsumerState<ExampleApp> {
  late IdentityMessages _identityMessages;
  bool _messagesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final localizationService = ref.read(myLocalizationServiceProvider);

    try {
      await localizationService.loadModuleMessages(
        IdentityMessages.module,
        'en',
        modulePath: 'packages/zen_ui_identity/lib/src/l10n',
      );
    } catch (e) {
      debugPrint('Error loading messages: $e');
    }

    _identityMessages = IdentityMessages(localizationService, 'en');

    if (mounted) {
      setState(() => _messagesLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_messagesLoaded) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // Router configuration must be rebuilt if auth state changes to support redirection?
    // GoRouter 'refreshListenable' usually takes a notifier.
    // identitySessionStoreProvider is a StateNotifierProvider, we can use it.

    final router = GoRouter(
      debugLogDiagnostics: true,
      initialLocation: '/profile', // Will redirect to login if not auth
      redirect: (context, state) {
        final authState = ref.read(identitySessionStoreProvider);
        final isAuthenticated = authState.value != null;

        final isLoginRoute =
            state.uri.path == '/login' ||
            state.uri.path == '/register' ||
            state.uri.path == '/restore-password';

        if (!isAuthenticated && !isLoginRoute) {
          return '/login';
        }

        if (isAuthenticated && isLoginRoute) {
          return '/profile';
        }

        return null;
      },
      refreshListenable: IdentityListenable(ref),
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => LoginScreen(
            messages: _identityMessages,
            onLoginSuccess: () => context.go('/profile'),
            onRegisterClick: () => context.push('/register'),
            onForgotPasswordClick: () => context.push('/restore-password'),
          ),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => RegisterScreen(
            messages: _identityMessages,
            onRegisterSuccess: () => context.go('/profile'),
            onLoginClick: () => context.go('/login'),
          ),
        ),
        GoRoute(
          path: '/restore-password',
          builder: (context, state) => RestorePasswordScreen(
            messages: _identityMessages,
            onRestoreSuccess: () => context.go('/login'),
            onBackClick: () => context.pop(),
          ),
        ),

        // Main Authenticated Routes using HomeScreen wrapper
        GoRoute(
          path: '/profile',
          builder: (context, state) =>
              HomeScreen(initialIndex: 0, messages: _identityMessages),
        ),
        GoRoute(
          path: '/roles',
          builder: (context, state) =>
              HomeScreen(initialIndex: 1, messages: _identityMessages),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Identity UI Example',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        extensions: [IdentityThemeExtension.fallback()],
      ),
      routerConfig: router,
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  final IdentityMessages messages;

  const HomeScreen({
    super.key,
    required this.initialIndex,
    required this.messages,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex) {
      _selectedIndex = widget.initialIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(myLocalizationServiceProvider);

    return ZenNavigation(
      selectedIndex: _selectedIndex,
      onItemSelected: (index) {
        setState(() => _selectedIndex = index);
        // Optional: Update URL without full reload?
        // Or if we want deep linking persistence, we should context.go again.
        // But context.go rebuilds this widget.
        // If we want ZenNavigation to handle tabs, we use setState.
        // If we want URL reflection, we verify if index changed relative to route.
        if (index == 0) context.go('/profile');
        if (index == 1) context.go('/roles');
      },
      localization: loc,
      language: 'en',
      items: [
        ZenNavigationItem(
          id: 'profile',
          label: widget.messages.profileTitle,
          icon: Icons.person,
          builder: (context) =>
              ProfileScreen(messages: widget.messages, onLogoutSuccess: () {}),
        ),
        ZenNavigationItem(
          id: 'roles',
          label: 'Roles',
          icon: Icons.security,
          builder: (context) => AuthorityRolesScreen(messages: widget.messages),
        ),
      ],
    );
  }
}

/// Listens to authentication state and notifies GoRouter.
class IdentityListenable extends ChangeNotifier {
  IdentityListenable(WidgetRef ref) {
    ref.listen(identitySessionStoreProvider, (prev, next) => notifyListeners());
  }
}
