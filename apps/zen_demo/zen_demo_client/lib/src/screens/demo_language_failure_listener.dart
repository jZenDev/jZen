import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/demo_localizations.dart';
import '../language_choice.dart';
import '../providers.dart';

/// Says that a chosen language could not be saved.
///
/// It wraps `home` rather than living in the picker: the server may answer after the person has
/// moved to another screen, and a report owned by the picker would be lost with it. It has to be
/// inside `MaterialApp`, below the `Navigator` that `showZenMessage` needs.
class DemoLanguageFailureListener extends ConsumerWidget {
  const DemoLanguageFailureListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<LanguageSaveFailure?>(languageChoiceProvider, (_, failure) {
      if (failure == null) return;
      // Looked up by the chosen locale, not taken from the context: a failure can arrive before
      // the frame that relocalizes the tree, and the sentence belongs in the new language.
      final messages = lookupDemoLocalizations(ref.read(localeProvider));
      showZenMessage(context, switch (failure) {
        LanguageSaveFailure.device => messages.languageNotSavedOnDevice,
        LanguageSaveFailure.account => messages.languageNotSavedToAccount,
      });
    });

    return child;
  }
}
