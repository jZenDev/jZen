import 'package:zen_ui_store/zen_ui_store.dart';

import '../../generated/zen_demo_local/v1/chore.pb.dart';
import '../l10n/generated/local_localizations.dart';
import 'device_session.dart';
import 'priority_label.dart';

/// How a chore is named and its fields are worded when two devices disagree about it.
List<ZenConflictSource<Chore>> choreConflictSources(
  DeviceSession session,
  LocalDemoLocalizations messages,
) => [
  ZenConflictSource<Chore>(
    collection: session.chores.collection,
    title: (chore) => chore.title,
    fieldLabel: (field) => switch (field) {
      2 => messages.titleField,
      3 => messages.noteField,
      4 => messages.doneField,
      5 => messages.priorityField,
      _ => null,
    },
    fieldValue: (chore, field) => switch (field) {
      4 => chore.done ? messages.choreDone : messages.choreOpen,
      5 => priorityLabel(messages, chore.priority),
      _ => null,
    },
  ),
];
