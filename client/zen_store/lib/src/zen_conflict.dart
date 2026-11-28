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

  /// Every version in dispute, latest first: between them, each surviving value of each field in
  /// [fields], each delete, and each edit a delete had not seen. Devices holding the same state
  /// answer the same sides.
  ///
  /// Usually one side per device that took part. **A device can have several**
  /// ([ZenConflictSide.device] repeats): two devices set a field to the same value, one merged the
  /// two into one version under the other's name, and that other device changed the field again
  /// before receiving the merge. Both values are then under its name, each with its own side. So
  /// never index sides by device, and never take the number of sides for the number of devices.
  /// To ask whether the sides agree about something, compare the values of all of them.
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

/// One version a [ZenConflict] is between, and the device it is attributed to.
@immutable
final class ZenConflictSide<T> {
  /// The device's id.
  final String device;

  /// The name a person knows the device by, as that device gave it.
  final String deviceName;

  /// When that device wrote it, by its own clock — for showing, never deciding. For a device with
  /// one side, its last write to the record; for one with several, the write that sets this side
  /// apart (two sides can still share a time).
  final DateTime at;

  /// The record with this side's values of the disputed fields, or null when this side is a
  /// delete. A disputed field this device did not write is shown from its latest version.
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
