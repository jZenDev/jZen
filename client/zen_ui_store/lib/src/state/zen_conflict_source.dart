import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

/// One collection whose conflicts the conflict screens show, and how to show its records.
///
/// Only [title] is required: a person has to recognise *which* record is in question ("Groceries,
/// 12 Oct"), and only the application knows what does that. Each disputed field is shown by its
/// label and value, which default to the proto field's own name and value — readable, if plain —
/// and which [fieldLabel] and [fieldValue] replace with the app's words and formatting (a
/// currency, a date, a category's name instead of its id).
final class ZenConflictSource<T extends GeneratedMessage> {
  /// The collection to look in.
  final ZenCollection<T> collection;

  /// How the person recognises a record.
  final String Function(T value) title;

  /// The person's name for a field, by proto field number; null falls back to the proto name.
  final String? Function(int field)? fieldLabel;

  /// A field's value as the person reads it; null falls back to the proto value.
  final String? Function(T value, int field)? fieldValue;

  /// Describes how to show [collection]'s conflicts.
  const ZenConflictSource({
    required this.collection,
    required this.title,
    this.fieldLabel,
    this.fieldValue,
  });

  /// This collection's conflicts as the screens show them. The typed work happens here, inside
  /// the generic class, so the screens can hold sources of different message types in one list.
  @internal
  ZenResult<List<ZenConflictView>> views({required String notSet}) {
    final List<ZenConflict<T>> conflicts;
    switch (collection.conflicts()) {
      case ZenSuccess(:final data):
        conflicts = data;
      case ZenFailure(:final error):
        return ZenResult.err(error);
    }
    return ZenResult.ok([
      for (final conflict in conflicts)
        ZenConflictView(
          collection: collection.name,
          id: conflict.id,
          title: _title(conflict),
          sides: [
            for (final side in conflict.sides)
              ZenConflictSideView(
                deviceName: side.deviceName,
                at: side.at,
                isDelete: side.isDelete,
                fields: side.value == null
                    ? const []
                    : [
                        for (final field in _shownFields(conflict))
                          (_label(side.value!, field), _value(side.value!, field) ?? notSet),
                      ],
                keep: () => collection.resolve(conflict.id, side.value),
              ),
          ],
        ),
    ]);
  }

  String? _title(ZenConflict<T> conflict) {
    for (final side in conflict.sides) {
      if (side.value case final value?) return title(value);
    }
    return null;
  }

  /// The disputed fields, or — for a delete against an edit, where no field is disputed — every
  /// field the edited side has, so the person sees what deleting would throw away.
  List<int> _shownFields(ZenConflict<T> conflict) {
    if (conflict.fields.isNotEmpty) return conflict.fields.toList()..sort();
    final edited = conflict.sides.map((side) => side.value).nonNulls.firstOrNull;
    if (edited == null) return const [];
    return [
      for (final field in edited.info_.fieldInfo.keys.toList()..sort())
        if (edited.hasField(field)) field,
    ];
  }

  String _label(T value, int field) {
    if (fieldLabel?.call(field) case final label?) return label;
    final name = value.info_.fieldInfo[field]?.name ?? '';
    return name.isEmpty ? '#$field' : name;
  }

  String? _value(T value, int field) {
    if (fieldValue?.call(value, field) case final text?) return text;
    if (!value.hasField(field)) return null;
    final raw = value.getField(field);
    return switch (raw) {
      ProtobufEnum(:final name) => name,
      List<Object?>() => raw.join(', '),
      GeneratedMessage() => raw.toString().trim(),
      _ => '$raw',
    };
  }
}

/// A conflict as the screens show it, with no message type left in it.
@internal
@immutable
final class ZenConflictView {
  final String collection;
  final String id;

  /// How the person recognises the record; null when every side is a delete.
  final String? title;
  final List<ZenConflictSideView> sides;

  const ZenConflictView({
    required this.collection,
    required this.id,
    required this.title,
    required this.sides,
  });
}

/// One device's side of a conflict, as the screens show it.
@internal
@immutable
final class ZenConflictSideView {
  final String deviceName;
  final DateTime at;
  final bool isDelete;

  /// Each shown field's label and value.
  final List<(String, String)> fields;

  /// Resolves the conflict with this side.
  final Future<ZenResult<Object?>> Function() keep;

  const ZenConflictSideView({
    required this.deviceName,
    required this.at,
    required this.isDelete,
    required this.fields,
    required this.keep,
  });
}
