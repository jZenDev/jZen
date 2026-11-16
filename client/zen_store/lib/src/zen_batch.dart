import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';

import 'zen_collection.dart';
import 'zen_proto_fields.dart';
import 'zen_store.dart';

/// Writes and deletes, across collections, that [ZenStore.writeAll] saves as one: every one
/// reaches the disk, or none does, even if the device loses power half way.
///
/// ```dart
/// final batch = ZenBatch()
///   ..delete(records, 'r1')
///   ..delete(records, 'r2')
///   ..delete(accounts, 'a1');
/// final result = await store.writeAll(batch);
/// ```
///
/// A batch is a list, not a transaction object: nothing is read or checked until `writeAll`
/// runs it, and the same batch can be run again. Each record may appear in it once.
final class ZenBatch {
  final List<ZenBatchOperation> _operations = [];

  /// How many writes and deletes the batch holds.
  int get length => _operations.length;

  /// Whether the batch holds nothing.
  bool get isEmpty => _operations.isEmpty;

  /// Adds the creation or replacement of the record [id] in [collection] with [value], with the
  /// meaning of [ZenCollection.put].
  void put<T extends GeneratedMessage>(ZenCollection<T> collection, String id, T value) {
    _operations.add(
      ZenBatchOperation._(
        collection.owner,
        collection.name,
        id,
        splitFields(value.writeToBuffer()),
      ),
    );
  }

  /// Adds the deletion of the record [id] in [collection], with the meaning of
  /// [ZenCollection.delete]: the whole batch fails with a [ZenNotFoundError] if there is no such
  /// record when it runs.
  void delete<T extends GeneratedMessage>(ZenCollection<T> collection, String id) {
    _operations.add(ZenBatchOperation._(collection.owner, collection.name, id, null));
  }

  /// The operations in the order they were added.
  @internal
  List<ZenBatchOperation> get operations => List.unmodifiable(_operations);
}

/// One write or delete of a [ZenBatch].
@internal
final class ZenBatchOperation {
  /// The store the collection belongs to.
  final ZenStore store;

  /// The collection's name.
  final String collection;

  /// The record's id.
  final String id;

  /// The record's fields by proto field number, or null for a delete.
  final Map<int, Uint8List>? fields;

  const ZenBatchOperation._(this.store, this.collection, this.id, this.fields);

  /// Whether this operation deletes the record.
  bool get isDelete => fields == null;
}
