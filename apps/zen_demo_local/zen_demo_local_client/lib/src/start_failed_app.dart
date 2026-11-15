import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'demo_local_theme.dart';
import 'l10n/generated/local_localizations.dart';

/// Shown when the data could not be opened. It says why and changes nothing: the person's data is
/// never replaced by an empty store to get past a failure.
class StartFailedApp extends StatelessWidget {
  final ZenError error;

  const StartFailedApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: const [
      ...LocalDemoLocalizations.localizationsDelegates,
      ...GlobalMaterialLocalizations.delegates,
      zenWidgetsLocaleDelegate,
    ],
    supportedLocales: [for (final tag in ZenLocales.shipped) Locale(tag)],
    theme: demoLocalTheme(Brightness.light),
    darkTheme: demoLocalTheme(Brightness.dark),
    home: Builder(
      builder: (context) {
        final messages = LocalDemoLocalizations.of(context);
        return ZenPageScaffold(
          title: messages.startFailedTitle,
          automaticallyImplyLeading: false,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(messages.startFailedHint(error.message)),
          ),
        );
      },
    ),
  );
}
