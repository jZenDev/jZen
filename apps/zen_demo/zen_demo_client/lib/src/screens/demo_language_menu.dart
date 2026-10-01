import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

import '../providers.dart';

/// The language switcher: a popup of the supported locales, each under its own name.
class DemoLanguageMenu extends ConsumerWidget {
  const DemoLanguageMenu({super.key, required this.label});

  final String label;

  /// The language each supported locale is offered under, written in that language.
  /// Endonyms are deliberately not localized, so they are the one place in the app that is
  /// not an ARB entry.
  static const Map<String, String> _endonyms = {
    ZenLocales.en: 'English',
    ZenLocales.uk: 'Українська',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return PopupMenuButton<Locale>(
      icon: const Icon(Icons.translate),
      tooltip: label,
      initialValue: locale,
      // Setting the locale does two things at once (ADR-007 + ADR-009): Localizations
      // re-renders this frame in the new language, and the very next request carries it as
      // Accept-Language, because ZenClient reads this same notifier per request.
      onSelected: (value) => ref.read(localeProvider.notifier).setLocale(value),
      itemBuilder: (context) => [
        for (final tag in demoSupportedLocales)
          PopupMenuItem(value: Locale(tag), child: Text(_endonyms[tag]!)),
      ],
    );
  }
}
