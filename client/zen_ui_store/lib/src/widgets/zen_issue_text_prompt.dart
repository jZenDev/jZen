import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/store_localizations.dart';

/// Asks for a short text for an issue action; pops the trimmed text, or nothing on cancel.
class ZenIssueTextPrompt extends StatefulWidget {
  /// The action's label, shown as the question.
  final String title;

  /// The field's label.
  final String fieldLabel;

  const ZenIssueTextPrompt({super.key, required this.title, required this.fieldLabel});

  @override
  State<ZenIssueTextPrompt> createState() => _ZenIssueTextPromptState();
}

class _ZenIssueTextPromptState extends State<ZenIssueTextPrompt> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final messages = StoreLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 12),
          ZenTextField(
            label: widget.fieldLabel,
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          // Only this button follows the text, so a keystroke does not rebuild the whole prompt.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => ZenButton(
              label: messages.issueContinue,
              onPressed: value.text.trim().isEmpty ? null : _submit,
            ),
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
