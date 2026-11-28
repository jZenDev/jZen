import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../language_choice.dart';
import '../providers.dart';

/// The language switcher: a menu of the supported locales, each under its own name, the one in
/// use marked.
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
    return ZenActionMenu(
      label: label,
      icon: Icons.translate,
      actions: [
        for (final tag in demoSupportedLocales)
          ZenMenuAction(
            label: _endonyms[tag]!,
            selected: Locale(tag) == locale,
            // The device first, then the account (see LanguageChoice). Setting the locale does
            // two things at once (ADR-007 + ADR-009): Localizations re-renders this frame in the
            // new language, and the very next request carries it as Accept-Language, because
            // ZenClient reads that same notifier per request.
            onPressed: () => ref.read(languageChoiceProvider.notifier).choose(Locale(tag)),
          ),
      ],
    );
  }
}
