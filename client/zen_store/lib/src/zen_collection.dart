import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';

import 'zen_conflict.dart';
import 'zen_proto_fields.dart';
import 'zen_record_state.dart';
import 'zen_storage_error.dart';
import 'zen_store.dart';

/// The records of one kind in a [ZenStore], read and written as the proto message [T].
///
/// Every call answers with a [ZenResult], as `ZenClient` does, so a repository written against a
/// server can keep its shape when it is pointed at a store instead. Reads come from memory and
/// are synchronous; a write's future completes once it is on disk.
///
/// A record in conflict ([conflicts]) is still read — with each disputed field taken from its
/// latest version, so nothing disappears from a screen — but it refuses [put] and [delete] with a
/// [ZenConflictError] until [resolve] settles it.
final class ZenCollection<T extends GeneratedMessage> {
  final ZenStore _store;
  final T Function(List<int> bytes) _decode;

  /// The collection's name, the same on every device.
  final String name;

  /// Use [ZenStore.collection].
  @internal
  ZenCollection.internal(this._store, this.name, this._decode);

  /// The record [id], or a [ZenNotFoundError] if it does not exist or was deleted.
  ZenResult<T> get(String id) {
    final record = _store.recordFor(name, id);
    if (record == null || record.isDeleted) return ZenResult.err(_notFound(id));
    return _read(id, record.visibleBytes());
  }

  /// Every record in the collection, ordered by id.
  ZenResult<List<T>> list() {
    final values = <T>[];
    for (final record in _store.recordsIn(name)) {
      if (record.isDeleted) continue;
      switch (_read(record.id, record.visibleBytes())) {
        case ZenSuccess(:final data):
          values.add(data);
        case ZenFailure(:final error):
          return ZenResult.err(error);
      }
    }
    return ZenResult.ok(values);
  }

  /// Creates or replaces the record [id] with [value], and returns [value].
  ///
  /// Only the fields that differ from the stored record count as this device's edit, which is
  /// what lets another device's edit to a different field survive the next sync.
  Future<ZenResult<T>> put(String id, T value) {
    if (_invalidId(id) case final error?) return Future.value(ZenResult.err(error));
    final fields = splitFields(value.writeToBuffer());
    return _store.write<T>(name, id, (current) {
      if (current != null && current.isInConflict) return ZenResult.err(_inConflict(id));
      return ZenResult.ok((fields, value));
    });
  }

  /// Deletes the record [id] and returns what it held, or a [ZenNotFoundError] if there is none.
  ///
  /// A delete syncs like any write. If another device edits the record without having seen the
  /// delete, the record comes back as a conflict for a person to settle, never silently gone.
  Future<ZenResult<T>> delete(String id) => _store.write<T>(name, id, (current) {
    if (current == null || current.isDeleted) return ZenResult.err(_notFound(id));
    if (current.isInConflict) return ZenResult.err(_inConflict(id));
    return switch (_read(id, current.visibleBytes())) {
      ZenSuccess(:final data) => ZenResult.ok((null as Map<int, Uint8List>?, data)),
      ZenFailure(:final error) => ZenResult.err(error),
    };
  });

  /// Every record in this collection waiting for a person to choose between devices' versions.
  ZenResult<List<ZenConflict<T>>> conflicts() {
    final found = <ZenConflict<T>>[];
    for (final record in _store.recordsIn(name)) {
      if (!record.isInConflict) continue;
      switch (_conflict(record)) {
        case ZenSuccess(:final data):
          found.add(data);
        case ZenFailure(:final error):
          return ZenResult.err(error);
      }
    }
    return ZenResult.ok(found);
  }

  /// The conflict on record [id], or null when it has none.
  ZenResult<ZenConflict<T>?> conflictFor(String id) {
    final record = _store.recordFor(name, id);
    if (record == null || !record.isInConflict) return const ZenResult.ok(null);
    return switch (_conflict(record)) {
      ZenSuccess(:final data) => ZenResult.ok(data),
      ZenFailure(:final error) => ZenResult.err(error),
    };
  }

  /// Settles the conflict on [id] with the person's choice: [value] — one side's, or a version
  /// they combined — or null to delete the record. The choice replaces every side on every device
  /// at its next sync. Fails with a [ZenValidationError] when [id] is not in conflict, because a
  /// resolution is never the way to make an ordinary write.
  Future<ZenResult<T?>> resolve(String id, T? value) {
    final fields = value == null ? null : splitFields(value.writeToBuffer());
    return _store.write<T?>(name, id, (current) {
      if (current == null || !current.isInConflict) {
        return ZenResult.err(ZenValidationError('$name/$id has no conflict to resolve.'));
      }
      return ZenResult.ok((fields, value));
    }, settle: true);
  }

  /// Fires whenever this collection's contents or conflicts change, by a local write or a sync.
  Stream<void> get changes => _store.changes.where((names) => names.contains(name));

  ZenResult<ZenConflict<T>> _conflict(ZenRecordState record) {
    final sides = <ZenConflictSide<T>>[];
    for (final author in record.conflictAuthors) {
      T? value;
      if (!record.deletedBy(author)) {
        switch (_read(record.id, record.visibleBytes(chosen: record.versionsBy(author)))) {
          case ZenSuccess(:final data):
            value = data;
          case ZenFailure(:final error):
            return ZenResult.err(error);
        }
      }
      sides.add(
        ZenConflictSide(
          device: author,
          deviceName: _store.nameOf(author),
          at: DateTime.fromMillisecondsSinceEpoch(record.lastWriteBy(author)),
          value: value,
        ),
      );
    }
    return ZenResult.ok(
      ZenConflict(
        collection: name,
        id: record.id,
        sides: sides,
        fields: record.conflictingFields,
        isDeleteConflict: record.isDeleteConflict,
      ),
    );
  }

  ZenResult<T> _read(String id, Uint8List bytes) {
    try {
      return ZenResult.ok(_decode(bytes));
    } on InvalidProtocolBufferException catch (e, stack) {
      return ZenResult.err(
        ZenStorageError('$name/$id is not a readable ${T.toString()}: $e', stackTrace: stack),
      );
    }
  }

  /// A record id travels as part of a CloudKit record name, which is printable ASCII of at most
  /// 255 characters; an id that would not fit is refused here rather than at the first sync.
  static ZenValidationError? _invalidId(String id) {
    if (id.isEmpty || id.length > 190 || !id.codeUnits.every((c) => c > 0x20 && c < 0x7f)) {
      return ZenValidationError('"$id" is not a record id: 1 to 190 printable ASCII characters.');
    }
    return null;
  }

  ZenNotFoundError _notFound(String id) => ZenNotFoundError('$name/$id does not exist.');

  ZenConflictError _inConflict(String id) => ZenConflictError(
    '$name/$id was changed differently on two devices; resolve the conflict before writing it.',
  );
}
