import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

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
