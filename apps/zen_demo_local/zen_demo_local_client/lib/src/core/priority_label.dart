import '../../generated/zen_demo_local/v1/chore.pb.dart';
import '../l10n/generated/local_localizations.dart';

/// The person's word for a priority, in the language the app is shown in.
String priorityLabel(LocalDemoLocalizations messages, Priority priority) => switch (priority) {
  Priority.PRIORITY_LOW => messages.priorityLow,
  Priority.PRIORITY_HIGH => messages.priorityHigh,
  _ => messages.priorityNormal,
};
