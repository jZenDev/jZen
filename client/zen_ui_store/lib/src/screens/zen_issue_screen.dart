import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';
import '../state/zen_issue_source.dart';
import '../widgets/zen_issue_choice_prompt.dart';
import '../widgets/zen_issue_text_prompt.dart';

/// An application's own issue, in its words, with a button for each of the application's actions.
/// Opened from `ZenConflictsScreen`.
class ZenIssueScreen extends StatefulWidget {
  /// The issue shown.
  final ZenIssue issue;

  /// Called once an action has succeeded.
  final VoidCallback onDone;

  const ZenIssueScreen({super.key, required this.issue, required this.onDone});

  @override
  State<ZenIssueScreen> createState() => _ZenIssueScreenState();
}

class _ZenIssueScreenState extends State<ZenIssueScreen> {
  bool _busy = false;
  String? _failure;

  Future<void> _run(ZenIssueAction action) async {
    if (_busy) return;
    // Busy from the tap on, so a second tap cannot open a second prompt or run twice.
    setState(() {
      _busy = true;
      _failure = null;
    });
    final Future<ZenResult<Object?>>? running = switch (action) {
      ZenPlainIssueAction() => action.run(),
      ZenChoiceIssueAction() => await _ask(
        ZenIssueChoicePrompt(title: action.label, choices: action.choices),
        action.run,
      ),
      ZenTextIssueAction() => await _ask(
        ZenIssueTextPrompt(title: action.label, fieldLabel: action.fieldLabel),
        action.run,
      ),
    };
    if (running == null) {
      // Cancelled: nothing runs and the issue stays.
      if (mounted) setState(() => _busy = false);
      return;
    }
    final result = await running;
    if (!mounted) return;
    if (result.isSuccess) {
      widget.onDone();
    } else {
      setState(() {
        _busy = false;
        _failure = result.errorOrNull?.message;
      });
    }
  }

  /// Asks [prompt] and returns the action's run with the answer; null when cancelled.
  Future<Future<ZenResult<Object?>>?> _ask(
    Widget prompt,
    Future<ZenResult<Object?>> Function(String) run,
  ) async {
    final answer = await showAdaptivePresentation<String>(context, builder: (_) => prompt);
    return answer == null || !mounted ? null : run(answer);
  }

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    final theme = Theme.of(context);
    return ZenPageScaffold(
      title: messages.issueTitle,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            header: true,
            child: Text(widget.issue.title, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Text(widget.issue.description, style: theme.textTheme.bodyLarge),
          if (_failure != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                messages.issueFailed(_failure!),
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ],
          for (final action in widget.issue.actions) ...[
            const SizedBox(height: 16),
            ZenButton(
              label: action.label,
              variant: ZenButtonVariant.secondary,
              onPressed: _busy ? null : () => _run(action),
            ),
          ],
        ],
      ),
    );
  }
}
