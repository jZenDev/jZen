import 'package:flutter/foundation.dart' show listEquals;
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
    return ZenResult.ok([for (final conflict in conflicts) _view(conflict, notSet)]);
  }

  ZenConflictView _view(ZenConflict<T> conflict, String notSet) => ZenConflictView(
    collection: collection.name,
    id: conflict.id,
    title: _title(conflict),
    latest: () => switch (collection.conflictFor(conflict.id)) {
      ZenSuccess(:final data) => ZenResult.ok(data == null ? null : _view(data, notSet)),
      ZenFailure(:final error) => ZenResult.err(error),
    },
    sides: [
      for (final (index, side) in conflict.sides.indexed)
        ZenConflictSideView(
          device: side.device,
          deviceName: side.deviceName,
          number: _number(conflict, index),
          at: side.at,
          isDelete: side.isDelete,
          fields: side.value == null
              ? const []
              : [
                  for (final field in _shownFields(conflict))
                    (_label(side.value!, field), _value(side.value!, field) ?? notSet),
                ],
          keep: () => collection.resolve(
            conflict.id,
            side.value,
            // Asked inside the write's turn: what a sync queued before it brings is seen too.
            expect: (now) => _isSame(conflict, now)
                ? null
                : ZenStaleChoiceError(
                    '${collection.name}/${conflict.id} changed since its versions were shown.',
                  ),
          ),
        ),
    ],
  );

  /// Which of the sides under one name the side at [index] is, and how many there are — one
  /// device with two versions, or two devices a person gave the same name. Null for a name only
  /// one side has.
  (int, int)? _number(ZenConflict<T> conflict, int index) {
    final name = conflict.sides[index].deviceName;
    final named = [
      for (final (i, side) in conflict.sides.indexed)
        if (side.deviceName == name) i,
    ];
    return named.length < 2 ? null : (named.indexOf(index) + 1, named.length);
  }

  /// Whether [now] is exactly the conflict [shown]: the same sides, each a device with a version.
  /// A device can have several, so they are matched one for one and never looked up by device. A
  /// sync can add a side or change one after a screen was drawn.
  bool _isSame(ZenConflict<T> shown, ZenConflict<T> now) {
    if (now.sides.length != shown.sides.length) return false;
    if (now.fields.length != shown.fields.length || !now.fields.containsAll(shown.fields)) {
      return false;
    }
    final unmatched = now.sides.toList();
    return shown.sides.every((side) {
      final match = unmatched.indexWhere(
        (other) => other.device == side.device && _isSameValue(other.value, side.value),
      );
      if (match < 0) return false;
      unmatched.removeAt(match);
      return true;
    });
  }

  /// Compared as encoded, not with `==`: a message holding a NaN is not equal to itself, which
  /// would make an unchanged record look changed every time and leave it impossible to settle.
  bool _isSameValue(T? a, T? b) =>
      a == null || b == null ? a == b : listEquals(a.writeToBuffer(), b.writeToBuffer());

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

/// A choice refused because the record's conflict is no longer the one the person was shown. A
/// type of its own, so that the screens never mistake another failure for it.
@internal
final class ZenStaleChoiceError extends ZenError {
  const ZenStaleChoiceError(super.message);
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

  /// The record's conflict as the store holds it now, or null once it is settled.
  final ZenResult<ZenConflictView?> Function() latest;

  const ZenConflictView({
    required this.collection,
    required this.id,
    required this.title,
    required this.sides,
    required this.latest,
  });
}

/// One side of a conflict, as the screens show it. A device can have several.
@internal
@immutable
final class ZenConflictSideView {
  /// The device's id, which tells two devices of the same name apart.
  final String device;
  final String deviceName;

  /// This side's number among the sides under [deviceName], from 1, and how many there are; null
  /// when it is the only one, and the name alone tells it apart.
  final (int, int)? number;
  final DateTime at;
  final bool isDelete;

  /// Each shown field's label and value.
  final List<(String, String)> fields;

  /// Resolves the conflict with this side. Nothing is written when it fails, and the error says
  /// why: a [ZenStaleChoiceError] when the conflict is no longer as shown, a [ZenValidationError]
  /// when the record is no longer in conflict, anything else when the write itself failed.
  final Future<ZenResult<Object?>> Function() keep;

  const ZenConflictSideView({
    required this.device,
    required this.deviceName,
    required this.number,
    required this.at,
    required this.isDelete,
    required this.fields,
    required this.keep,
  });
}
