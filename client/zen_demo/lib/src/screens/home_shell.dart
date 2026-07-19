import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

import '../demo_messages.dart';
import '../providers.dart';
import 'dashboard_screen.dart';
import 'terms_screen.dart';

/// The authenticated shell: the reused ZenNavigation adaptive layout hosting the demo dashboard,
/// the localized terms, and the reused identity profile screen (which owns logout). Mirrors how
/// DartZen's main_screen.dart composed the demo's sections, but on the jZen navigation package.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({
    required this.localization,
    required this.demoMessages,
    required this.identityMessages,
    super.key,
  });

  final ZenLocalizationService localization;
  final DemoMessages demoMessages;
  final IdentityMessages identityMessages;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final demo = widget.demoMessages;

    final items = [
      ZenNavigationItem(
        id: 'home',
        label: demo.navHome,
        icon: Icons.home,
        builder: (context) => DemoDashboardScreen(messages: demo),
      ),
      ZenNavigationItem(
        id: 'terms',
        label: demo.navTerms,
        icon: Icons.description,
        builder: (context) => DemoTermsScreen(messages: demo),
      ),
      ZenNavigationItem(
        id: 'profile',
        label: demo.navProfile,
        icon: Icons.person,
        builder: (context) => ProfileScreen(messages: widget.identityMessages),
      ),
    ];

    return ZenNavigation(
      items: items,
      selectedIndex: _index,
      onItemSelected: (index) => setState(() => _index = index),
      localization: widget.localization,
      language: language,
    );
  }
}
