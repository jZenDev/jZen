import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The locale the example renders in. zen_ui_identity supplies its own wording for every
/// locale in ZenLocales.supported, so an app chooses the language and never the strings.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale(ZenLocales.fallback);

  void setLocale(Locale locale) => state = locale;
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);

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
  @override
  Widget build(BuildContext context) {
    // No loading gate any more: the strings are compiled into the binary, so there is no
    // bundle to fetch before the first frame (ADR-009).

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
            onLoginSuccess: () => context.go('/profile'),
            onRegisterClick: () => context.push('/register'),
            onForgotPasswordClick: () => context.push('/restore-password'),
          ),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => RegisterScreen(
            onRegisterSuccess: () => context.go('/profile'),
            onLoginClick: () => context.go('/login'),
          ),
        ),
        GoRoute(
          path: '/restore-password',
          builder: (context, state) => RestorePasswordScreen(
            onRestoreSuccess: () => context.go('/login'),
            onBackClick: () => context.pop(),
          ),
        ),

        // Main Authenticated Routes using HomeScreen wrapper
        GoRoute(
          path: '/profile',
          builder: (context, state) => const HomeScreen(initialIndex: 0),
        ),
        GoRoute(
          path: '/roles',
          builder: (context, state) => const HomeScreen(initialIndex: 1),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Identity UI Example',
      locale: ref.watch(localeProvider),
      // Per-package generation (ADR-009): each localized package brings its own delegate and
      // the app composes them.
      localizationsDelegates: const [
        ...IdentityLocalizations.localizationsDelegates,
        NavigationLocalizations.delegate,
      ],
      supportedLocales: IdentityLocalizations.supportedLocales,
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

  const HomeScreen({super.key, required this.initialIndex});

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
    final messages = IdentityLocalizations.of(context);

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
      items: [
        ZenNavigationItem(
          id: 'profile',
          label: messages.profileTitle,
          icon: Icons.person,
          builder: (context) => ProfileScreen(onLogoutSuccess: () {}),
        ),
        ZenNavigationItem(
          id: 'roles',
          label: messages.rolesTitle,
          icon: Icons.security,
          builder: (context) => const AuthorityRolesScreen(),
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
