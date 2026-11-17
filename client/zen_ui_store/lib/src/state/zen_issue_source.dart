import 'package:meta/meta.dart';
import 'package:zen_core/zen_core.dart';

/// Where an application reports problems that only it can see, so they wait for the person in the
/// same place as the store's own conflicts.
///
/// The store knows one kind of problem: a field set differently on two devices, or a delete
/// against an edit. After a sync an application can hold others that no device wrote — a goal
/// below zero after two withdrawals, a record on an account deleted elsewhere. The application
/// checks its own rules and lists what it found here; the banner counts them and the conflict list
/// shows them with the application's own actions. The application never fixes one silently.
///
/// [issues] runs whenever the store changes (a local write or a sync), so re-check there and
/// return what is wrong *now*; an issue that is no longer true simply is not returned and
/// leaves the list. Pass [changes] when the answer can change for another reason, such as an action
/// that does not write to the store: the banner then needs it to count again.
final class ZenIssueSource {
  /// What is wrong at this moment; empty when nothing is. Must be cheap: it runs on every change.
  final List<ZenIssue> Function() issues;

  /// Fires when [issues] may answer differently for a reason the store does not report.
  final Stream<void>? changes;

  /// Describes one application's source of issues.
  const ZenIssueSource({required this.issues, this.changes});

  /// How many issues the [sources] report together.
  @internal
  static int countIn(List<ZenIssueSource> sources) =>
      sources.fold(0, (total, source) => total + source.issues().length);
}

/// One thing the person has to look at, as the application words it.
@immutable
final class ZenIssue {
  /// Stable for as long as the problem is the same one, so a list can tell it from another.
  final String id;

  /// What it is, in a few words ("Groceries goal is below zero").
  final String title;

  /// What happened and what each action does, in the application's own words.
  final String description;

  /// The ways to settle it. Each is a button; at least one is needed, or the person has nothing to
  /// do about what they were just told.
  final List<ZenIssueAction> actions;

  /// Creates an issue.
  ZenIssue({
    required this.id,
    required this.title,
    required this.description,
    required this.actions,
  }) : assert(actions.isNotEmpty, 'an issue without an action leaves the person nothing to do');
}

/// One button on a [ZenIssue].
///
/// A plain action runs at once. A [choose] or [text] action first has `ZenIssueScreen` ask the
/// person for what it needs; cancelling the question runs nothing and leaves the issue. The three
/// kinds are separate types, so each one carries only what it can use and a `switch` over an
/// action is exhaustive.
@immutable
sealed class ZenIssueAction {
  /// The button's text.
  String get label;

  /// A plain action: [run] takes nothing. A failure is shown to the person, and the issue stays.
  const factory ZenIssueAction({
    required String label,
    required Future<ZenResult<Object?>> Function() run,
  }) = ZenPlainIssueAction;

  /// An action that needs one of [choices] (id, label) before it can run; [run] gets the chosen id.
  const factory ZenIssueAction.choose({
    required String label,
    required List<(String, String)> choices,
    required Future<ZenResult<Object?>> Function(String id) run,
  }) = ZenChoiceIssueAction;

  /// An action that needs a short text, asked for with a field named [fieldLabel]; [run] gets the
  /// text, trimmed and never empty.
  const factory ZenIssueAction.text({
    required String label,
    required String fieldLabel,
    required Future<ZenResult<Object?>> Function(String text) run,
  }) = ZenTextIssueAction;
}

/// An action that runs as soon as it is pressed.
final class ZenPlainIssueAction implements ZenIssueAction {
  @override
  final String label;

  /// What it does.
  final Future<ZenResult<Object?>> Function() run;

  /// Creates a plain action.
  const ZenPlainIssueAction({required this.label, required this.run});
}

/// An action that runs with the candidate the person picked.
final class ZenChoiceIssueAction implements ZenIssueAction {
  @override
  final String label;

  /// The candidates as (id, label); at least one.
  final List<(String, String)> choices;

  /// What it does with the chosen id.
  final Future<ZenResult<Object?>> Function(String id) run;

  /// Creates a choice action.
  const ZenChoiceIssueAction({required this.label, required this.choices, required this.run})
    : assert(choices.length > 0, 'a choice needs at least one candidate');
}

/// An action that runs with a text the person typed.
final class ZenTextIssueAction implements ZenIssueAction {
  @override
  final String label;

  /// The text field's label.
  final String fieldLabel;

  /// What it does with the text.
  final Future<ZenResult<Object?>> Function(String text) run;

  /// Creates a text action.
  const ZenTextIssueAction({required this.label, required this.fieldLabel, required this.run});
}
