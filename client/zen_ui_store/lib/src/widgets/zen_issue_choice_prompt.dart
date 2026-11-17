import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';

/// Asks which of an issue action's candidates to use; pops the chosen id, or nothing on cancel.
class ZenIssueChoicePrompt extends StatefulWidget {
  /// The action's label, shown as the question.
  final String title;

  /// The candidates as (id, label).
  final List<(String, String)> choices;

  const ZenIssueChoicePrompt({super.key, required this.title, required this.choices});

  @override
  State<ZenIssueChoicePrompt> createState() => _ZenIssueChoicePromptState();
}

class _ZenIssueChoicePromptState extends State<ZenIssueChoicePrompt> {
  String? _chosen;

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: ZenRadioGroup<String>(
                label: widget.title,
                options: [
                  for (final (id, label) in widget.choices) ZenRadioOption(value: id, label: label),
                ],
                value: _chosen,
                onChanged: (id) => setState(() => _chosen = id),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ZenButton(
            label: messages.issueContinue,
            onPressed: _chosen == null ? null : () => Navigator.of(context).pop(_chosen),
          ),
          const SizedBox(height: 8),
          ZenButton(
            label: messages.cancelButton,
            variant: ZenButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
