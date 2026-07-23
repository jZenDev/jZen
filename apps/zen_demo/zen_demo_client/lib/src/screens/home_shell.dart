import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

import '../l10n/generated/demo_localizations.dart';
import 'dashboard_screen.dart';
import 'terms_screen.dart';

/// The authenticated shell: the reused ZenNavigation adaptive layout hosting the demo dashboard,
/// the localized terms, and the reused identity profile screen (which owns logout). Mirrors how
/// DartZen's main_screen.dart composed the demo's sections, but on the jZen navigation package.
///
/// Nothing here threads wording any more (ADR-009): the tab labels come from this app's own
/// generated accessors, and each hosted screen resolves its own package's accessors from the
/// context - so one locale change relabels the bar and re-renders the body together.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final demo = DemoLocalizations.of(context);

    final items = [
      ZenNavigationItem(
        id: 'home',
        label: demo.navHome,
        icon: Icons.home,
        builder: (context) => const DemoDashboardScreen(),
      ),
      ZenNavigationItem(
        id: 'terms',
        label: demo.navTerms,
        icon: Icons.description,
        builder: (context) => const DemoTermsScreen(),
      ),
      ZenNavigationItem(
        id: 'profile',
        label: demo.navProfile,
        icon: Icons.person,
        builder: (context) => const ProfileScreen(),
      ),
    ];

    return ZenNavigation(
      items: items,
      selectedIndex: _index,
      onItemSelected: (index) => setState(() => _index = index),
    );
  }
}
