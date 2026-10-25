import 'package:meta/meta.dart';

/// A record two devices changed in ways that cannot both be kept, waiting for a person to decide.
///
/// The store never decides one. Edits to different fields merge on their own, and so do equal
/// edits; what is left is either one field set to different values on two devices, or a delete on
/// one device and an edit on another. Every side is kept on disk and on every device until
/// `ZenCollection.resolve` is called, and until then the record refuses `put` and `delete` — so a
/// conflict cannot be settled by accident, by whichever screen happens to save next.
@immutable
final class ZenConflict<T> {
  /// The record's collection.
  final String collection;

  /// The record's id.
  final String id;

  /// What each device that took part has, latest first.
  final List<ZenConflictSide<T>> sides;

  /// The proto field numbers set to different values on different devices; empty when the
  /// conflict is only a delete against an edit.
  final Set<int> fields;

  /// Whether one side deleted the record while another edited it.
  final bool isDeleteConflict;

  /// Creates a conflict; the store builds these.
  const ZenConflict({
    required this.collection,
    required this.id,
    required this.sides,
    required this.fields,
    required this.isDeleteConflict,
  });

  @override
  String toString() => 'ZenConflict($collection/$id, fields: $fields, sides: $sides)';
}

/// One device's side of a [ZenConflict].
@immutable
final class ZenConflictSide<T> {
  /// The device's id.
  final String device;

  /// The name a person knows the device by, as that device gave it.
  final String deviceName;

  /// When that device last wrote to the record, by its own clock — for showing, never deciding.
  final DateTime at;

  /// The record as that device has it, or null when that device deleted it.
  final T? value;

  /// Creates a side; the store builds these.
  const ZenConflictSide({
    required this.device,
    required this.deviceName,
    required this.at,
    required this.value,
  });

  /// Whether this side is a delete.
  bool get isDelete => value == null;

  @override
  String toString() => '$deviceName at $at: ${isDelete ? 'deleted' : value}';
}
