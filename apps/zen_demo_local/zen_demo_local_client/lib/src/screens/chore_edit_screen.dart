import 'package:flutter/material.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../../generated/zen_demo_local/v1/chore.pb.dart';
import '../core/device_session.dart';
import '../core/priority_label.dart';
import '../l10n/generated/local_localizations.dart';

/// Makes or edits one chore. Each field is saved on its own merits: a device that changes only the
/// note writes only the note, so another device's edit to the priority merges instead of clashing.
class ChoreEditScreen extends StatefulWidget {
  final DeviceSession session;

  /// The chore to edit, or null to make a new one.
  final Chore? chore;

  const ChoreEditScreen({super.key, required this.session, this.chore});

  @override
  State<ChoreEditScreen> createState() => _ChoreEditScreenState();
}

class _ChoreEditScreenState extends State<ChoreEditScreen> {
  late final TextEditingController _title = TextEditingController(text: widget.chore?.title);
  late final TextEditingController _note = TextEditingController(text: widget.chore?.note);
  late bool _done = widget.chore?.done ?? false;
  late Priority _priority = widget.chore?.priority ?? Priority.PRIORITY_NORMAL;
  String? _titleError;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messages = LocalDemoLocalizations.of(context);
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = messages.titleRequired);
      return;
    }
    setState(() {
      _titleError = null;
      _busy = true;
    });
    final before = widget.chore;
    final after = (before?.deepCopy() ?? (Chore()..id = widget.session.newId()))
      ..title = title
      ..note = _note.text
      ..done = _done
      ..priority = _priority;
    // An existing chore is saved as the changes made here on top of what is stored now, so another
    // device's edit that arrived while this form was open is not sent back over.
    final result = before == null
        ? await widget.session.chores.save(after)
        : await widget.session.chores.edit(before, after);
    if (!mounted) return;
    await _finish(result, messages);
  }

  Future<void> _delete() async {
    final messages = LocalDemoLocalizations.of(context);
    setState(() => _busy = true);
    final result = await widget.session.chores.remove(widget.chore!.id);
    if (!mounted) return;
    await _finish(result, messages);
  }

  Future<void> _finish(ZenResult<Chore> result, LocalDemoLocalizations messages) async {
    switch (result) {
      case ZenSuccess():
        Navigator.of(context).pop();
      case ZenFailure(:final error):
        setState(() => _busy = false);
        showZenMessage(context, switch (error) {
          ZenConflictError() => messages.inConflict,
          ZenNotFoundError() => messages.choreGone,
          _ => messages.saveFailed(error.message),
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = LocalDemoLocalizations.of(context);
    final editing = widget.chore != null;
    return ZenPageScaffold(
      title: editing ? messages.editChoreTitle : messages.newChoreTitle,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ZenTextField(
            label: messages.titleField,
            controller: _title,
            errorText: _titleError,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          ZenTextField(
            label: messages.noteField,
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          ZenSwitchRow(
            label: messages.doneField,
            value: _done,
            onChanged: (value) => setState(() => _done = value),
          ),
          const SizedBox(height: 12),
          ZenSelect<Priority>(
            label: messages.priorityField,
            items: const [Priority.PRIORITY_LOW, Priority.PRIORITY_NORMAL, Priority.PRIORITY_HIGH],
            itemLabel: (priority) => priorityLabel(messages, priority),
            value: _priority,
            onChanged: (value) => setState(() => _priority = value),
          ),
          const SizedBox(height: 24),
          ZenButton(label: messages.save, onPressed: _busy ? null : _save, isLoading: _busy),
          if (editing) ...[
            const SizedBox(height: 12),
            ZenButton(
              label: messages.delete,
              variant: ZenButtonVariant.secondary,
              onPressed: _busy ? null : _delete,
            ),
          ],
        ],
      ),
    );
  }
}
