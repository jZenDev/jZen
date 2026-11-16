import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';

import 'zen_batch.dart';
import 'zen_collection.dart';
import 'zen_merge_policy.dart';
import 'zen_record_state.dart';
import 'zen_storage_error.dart';
import 'zen_store_cipher.dart';
import 'zen_store_log.dart';
import 'zen_sync_report.dart';
import 'zen_sync_transport.dart';

/// A Local application's data: proto messages by collection and id, encrypted on this device,
/// readable offline, and kept in step with the user's other devices by a [ZenSyncTransport].
///
/// **On disk** (the directory passed to [open]): `device.id`, this device's random id; `meta.zen`,
/// the device names, which records wait to be sent, and the transport's state; and the records,
/// sharded by a hash of their name into `records/00.zen` … `records/3f.zen` so a write rewrites
/// one small file, not everything. Every file but `device.id` is AES-256-GCM with the key passed to
/// [open], and rewritten atomically. All records are held in memory; reads are synchronous.
///
/// **A batch** ([writeAll]) spans shards, and a rename can only replace one file, so it first saves
/// every file it will rewrite, whole, as `journal.zen`, then rewrites them, then deletes the
/// journal. A journal found at [open] is a batch that was saved but not finished: it is finished
/// before anything is read. A crash before the journal exists leaves none of the batch, after it
/// all of the batch.
///
/// **Merging** never loses an edit without a person's say: edits to different fields merge,
/// equal edits merge, anything else becomes a `ZenConflict` (see [ZenCollection.conflicts]).
/// ADR-065 explains the design.
final class ZenStore {
  static const int _shardCount = 64;
  static final RegExp _collectionName = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final RegExp _hexId = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _journaledName = RegExp(r'^(meta\.zen|records/[0-9a-f]{2}\.zen)$');
  static final Random _random = Random.secure();
  static const String _metaName = 'meta.zen';
  static const String _journalName = 'journal.zen';

  final Directory _directory;
  final ZenStoreCipher _cipher;
  final int Function() _now;
  final Future<void> Function(int replaced, int total)? _afterFileReplaced;

  /// This device's id: how other devices tell its writes apart.
  final String deviceId;

  /// The name this device goes by in another device's conflict ("Alex's iPhone").
  final String deviceName;

  final Map<ZenStoreKey, ZenRecordState> _records;
  final Map<String, Map<int, ZenMergePolicy>> _policies = {};
  final Map<String, Set<int>> _explicitPresence = {};
  final Set<String> _deviceOnly = {};
  final Map<ZenStoreKey, Uint8List> _transportData;
  final List<Set<ZenStoreKey>> _shards;
  Map<String, String> _names;
  Set<String> _unsent;
  Uint8List? _transportState;
  bool _erasedEverywhere;

  final StreamController<void> _erasures = StreamController<void>.broadcast();
  final StreamController<Set<String>> _changes = StreamController<Set<String>>.broadcast();
  final StreamController<Set<String>> _unsentChanges = StreamController<Set<String>>.broadcast();
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  ZenStore._(
    this._directory,
    this._cipher,
    this._now,
    this._afterFileReplaced,
    this.deviceId,
    this.deviceName,
    this._records,
    this._transportData,
    this._names,
    this._unsent,
    this._transportState,
    this._erasedEverywhere,
  ) : _shards = List.generate(_shardCount, (_) => <ZenStoreKey>{}) {
    for (final key in _records.keys) {
      _shards[_shardOf(key)].add(key);
    }
  }

  /// Opens the store kept in [directory], creating it on first use, encrypted with [key] — 32
  /// random bytes the application keeps in the platform's secret storage (`zen_store_key`'s
  /// `ZenDeviceStoreKey`), never beside the data.
  ///
  /// [deviceName] is what a person sees in a conflict on another device ("Alex's iPhone").
  ///
  /// Fails with a [ZenStorageError] if a file does not decrypt — the wrong key, or a damaged or
  /// altered file — and writes nothing over it. Opening empty would make the next write replace
  /// the user's data; see [erase] for the deliberate way back.
  ///
  /// [now] supplies wall-clock milliseconds, which only ever label a write for a person.
  ///
  /// [afterFileReplaced] is for tests only: it runs after each file of a [writeAll] is replaced,
  /// with how many are done and how many there are, so a test can stop a batch half way — the way
  /// a power loss would — and reopen the directory.
  static Future<ZenResult<ZenStore>> open(
    Directory directory, {
    required String deviceName,
    required List<int> key,
    int Function()? now,
    @visibleForTesting Future<void> Function(int replaced, int total)? afterFileReplaced,
  }) async {
    if (deviceName.trim().isEmpty) {
      return ZenResult.err(const ZenValidationError('A device name is empty.'));
    }
    if (key.length != 32) {
      return ZenResult.err(ZenValidationError('A store key is 32 bytes, not ${key.length}.'));
    }
    final cipher = ZenStoreCipher(key);
    try {
      await Directory(_join(directory.path, 'records')).create(recursive: true);
      final deviceId = await _deviceId(directory);
      await _finishJournaledBatch(directory, cipher);
      final names = <String, String>{};
      var unsent = <String>{};
      Uint8List? transportState;
      var erased = false;
      final metaFile = File(_join(directory.path, 'meta.zen'));
      if (await metaFile.exists()) {
        final meta = decodeJson(
          await cipher.open(await metaFile.readAsBytes(), 'meta.zen'),
          'meta.zen',
        );
        if (meta['device'] != deviceId) {
          throw FormatException('meta.zen belongs to device ${meta['device']}, not this one');
        }
        for (final entry in (meta['names'] as Map<String, Object?>? ?? {}).entries) {
          if (entry.value case final String name) names[entry.key] = name;
        }
        unsent = {...(meta['unsent'] as List<Object?>? ?? []).whereType<String>()};
        if (meta['transport'] case final String state) transportState = base64Decode(state);
        erased = meta['erased'] == true;
      }
      final records = <ZenStoreKey, ZenRecordState>{};
      final transportData = <ZenStoreKey, Uint8List>{};
      for (var shard = 0; shard < _shardCount; shard++) {
        final file = File(_shardPath(directory, shard));
        if (!await file.exists()) continue;
        final name = _shardName(shard);
        final json = decodeJson(await cipher.open(await file.readAsBytes(), name), name);
        for (final raw in json['records'] as List<Object?>? ?? const []) {
          final record = decodeRecord(raw, names);
          final key = ZenStoreKey(record.collection, record.id);
          records[key] = record;
          if ((raw as Map<String, Object?>)['s'] case final String data) {
            transportData[key] = base64Decode(data);
          }
        }
      }
      names[deviceId] = deviceName;
      return ZenResult.ok(
        ZenStore._(
          directory,
          cipher,
          now ?? () => DateTime.now().millisecondsSinceEpoch,
          afterFileReplaced,
          deviceId,
          deviceName,
          records,
          transportData,
          names,
          unsent,
          transportState,
          erased,
        ),
      );
    } on FormatException catch (e, stack) {
      return ZenResult.err(
        ZenStorageError(
          'Refusing to open the store in ${directory.path}: ${e.message}. Nothing was written.',
          stackTrace: stack,
        ),
      );
    } on FileSystemException catch (e, stack) {
      return ZenResult.err(
        ZenStorageError('Cannot open the store in ${directory.path}: $e', stackTrace: stack),
      );
    }
  }

  /// Deletes the store in [directory]: every record and every change not yet sent.
  ///
  /// The way back from a store that will not open — its key was lost, so its files cannot be read
  /// by anyone — and only on the person's say: what was already synced comes back from the other
  /// devices at the next sync, and what was not is gone. Never call it to make an error go away.
  static Future<ZenResult<void>> erase(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      return const ZenResult.ok(null);
    } on FileSystemException catch (e, stack) {
      return ZenResult.err(
        ZenStorageError('Cannot erase the store in ${directory.path}: $e', stackTrace: stack),
      );
    }
  }

  /// A typed view of the collection [name] — lower-case letters, digits and `_`, starting with a
  /// letter — whose values are read back with [decode], the message's generated `fromBuffer`.
  ///
  /// [mergePolicies] declares, by proto field number, which fields merge on their own when two
  /// devices set them to different values ([ZenMergePolicy]). Declare the same policies on every
  /// device and every launch: a collection already declared with different ones throws an
  /// [ArgumentError], because two devices merging by different rules would not converge.
  ///
  /// A top-level proto3 field with implicit presence (a scalar or enum that is not `optional`) set
  /// to its default is stored as unset, since proto3 defines them as one value. The Dart runtime
  /// cannot tell an `optional` field from one that is not, so [explicitPresence] lists, by field
  /// number, the `optional` fields, where "set to the default" and "unset" stay different. Message,
  /// repeated and map fields are always explicit. Declared like [mergePolicies], and the same on
  /// every device.
  ///
  /// With [syncs] false the collection is device-only: its records are never in [unsent], never
  /// returned by [outgoing], and a record of that name arriving from a transport is refused — so
  /// they reach no other device and no sync service — yet [writeAll] saves them together with
  /// synced collections in one atomic step, and they are encrypted like all the others. Declare it
  /// before starting a transport, the same way on every launch.
  ZenCollection<T> collection<T extends GeneratedMessage>(
    String name,
    T Function(List<int> bytes) decode, {
    Map<int, ZenMergePolicy> mergePolicies = const {},
    Set<int> explicitPresence = const {},
    bool syncs = true,
  }) {
    if (!_collectionName.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'a collection name is [a-z][a-z0-9_]{0,63}');
    }
    for (final MapEntry(key: field, value: policy) in mergePolicies.entries) {
      if (field < 1) {
        throw ArgumentError.value(field, 'mergePolicies', 'a field number is 1 or more');
      }
      if (policy.subField case final subField? when subField < 1) {
        throw ArgumentError.value(subField, 'mergePolicies', 'a sub-field number is 1 or more');
      }
    }
    final declaredPresence = _explicitPresence[name];
    if (declaredPresence != null &&
        (declaredPresence.length != explicitPresence.length ||
            !declaredPresence.containsAll(explicitPresence))) {
      throw ArgumentError.value(
        explicitPresence,
        'explicitPresence',
        'the collection $name was already declared with different explicit-presence fields',
      );
    }
    if (declaredPresence != null && _deviceOnly.contains(name) == syncs) {
      throw ArgumentError.value(
        syncs,
        'syncs',
        'the collection $name was already declared ${syncs ? 'device-only' : 'synced'}',
      );
    }
    _explicitPresence[name] ??= Set.unmodifiable(explicitPresence);
    if (!syncs) _deviceOnly.add(name);
    final declared = _policies[name];
    if (declared != null && !_samePolicies(declared, mergePolicies)) {
      throw ArgumentError.value(
        mergePolicies,
        'mergePolicies',
        'the collection $name was already declared with different merge policies',
      );
    }
    if (declared == null && mergePolicies.isNotEmpty) {
      _policies[name] = Map.unmodifiable(mergePolicies);
      for (final record in recordsIn(name)) {
        record.applyPolicies(mergePolicies);
      }
    }
    return ZenCollection.internal(this, name, decode, _explicitPresence[name]!);
  }

  static bool _samePolicies(Map<int, ZenMergePolicy> a, Map<int, ZenMergePolicy> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  /// The collections whose contents or conflicts changed, once per write or sync that changed any.
  Stream<Set<String>> get changes => _changes.stream;

  /// How many records, across every collection, are waiting for a person to resolve a conflict.
  int get conflictCount => _records.values.where((record) => record.isInConflict).length;

  /// The collections that hold at least one conflict.
  Set<String> get collectionsInConflict => {
    for (final record in _records.values)
      if (record.isInConflict) record.collection,
  };

  /// A new random id for a record, 128 bits in hex, unique across devices without coordination.
  String newId() => _randomHex();

  // ── The transport's side ──────────────────────────────────────────────────────────────────────

  /// The records this device changed that no transport has confirmed saving, by name.
  Set<String> get unsent => Set.unmodifiable(_unsent.where((name) => !_isDeviceOnly(name)));

  bool _isDeviceOnly(String name) {
    if (_deviceOnly.isEmpty) return false;
    try {
      return _deviceOnly.contains(ZenStoreKey.parse(name).collection);
    } on FormatException {
      return false;
    }
  }

  /// Names that have just become unsent, after a local write or a merge that added to what the
  /// transport holds. A transport listens to send them.
  Stream<Set<String>> get unsentChanges => _unsentChanges.stream;

  /// The record [name] as it should be sent, or null if this store has no such record.
  ZenOutgoingRecord? outgoing(String name) {
    final ZenStoreKey key;
    try {
      key = ZenStoreKey.parse(name);
    } on FormatException {
      return null;
    }
    if (_deviceOnly.contains(key.collection)) return null;
    final record = _records[key];
    if (record == null) return null;
    return ZenOutgoingRecord(name, encodePayload(record, _names), _transportData[key]);
  }

  /// Merges records from the transport. A record whose merge holds something the transport's copy
  /// does not — a local edit it has not seen — becomes unsent, so it is sent again; one the
  /// transport already holds in full stops being unsent. A record that cannot be read is skipped
  /// and named in [ZenSyncReport.problems].
  Future<ZenResult<ZenSyncReport>> receive(List<ZenIncomingRecord> incoming) => _serialized(
    () async {
      if (_closed) return ZenResult.err(const ZenStorageError('The store is closed.'));
      if (_erasedEverywhere) return ZenResult.err(_erasedError);
      final records = Map.of(_records);
      final transportData = Map.of(_transportData);
      final names = Map.of(_names);
      final unsent = {..._unsent};
      final touched = <int>{};
      final changed = <String>{};
      final newlyUnsent = <String>{};
      final problems = <ZenSyncProblem>[];
      for (final item in incoming) {
        final ZenStoreKey key;
        final ZenRecordState theirs;
        try {
          key = ZenStoreKey.parse(item.name);
          theirs = decodePayload(item.payload, names);
          if (theirs.collection != key.collection || theirs.id != key.id) {
            throw FormatException('the payload is record ${theirs.collection}:${theirs.id}');
          }
        } on FormatException catch (e) {
          problems.add(ZenSyncProblem(item.name, e.message));
          continue;
        }
        if (_deviceOnly.contains(key.collection)) {
          problems.add(ZenSyncProblem(item.name, 'the collection is device-only'));
          continue;
        }
        final current = records[key];
        final merged = current?.copy() ?? theirs;
        final policies = _policies[key.collection] ?? const <int, ZenMergePolicy>{};
        if (current == null || merged.merge(theirs, policies: policies)) {
          changed.add(key.collection);
        }
        records[key] = merged;
        if (item.transportData case final data?) transportData[key] = data;
        names[deviceId] = deviceName;
        final holdsMore = !sameBytes(encodePayload(merged, names), encodePayload(theirs, names));
        if (holdsMore) {
          if (unsent.add(item.name)) newlyUnsent.add(item.name);
        } else {
          unsent.remove(item.name);
        }
        touched.add(_shardOf(key));
      }
      try {
        await _persist(records, transportData, names, unsent, _transportState, touched);
      } on FileSystemException catch (e, stack) {
        return ZenResult.err(ZenStorageError('Cannot save synced records: $e', stackTrace: stack));
      }
      _commit(records, transportData, names, unsent);
      if (changed.isNotEmpty) _changes.add(changed);
      if (newlyUnsent.isNotEmpty) _unsentChanges.add(newlyUnsent);
      return ZenResult.ok(
        ZenSyncReport(changed: changed, conflicts: conflictCount, problems: problems),
      );
    },
  );

  /// Records saves the transport completed. A record that changed after its payload was taken
  /// stays unsent, so the newer state is sent too.
  Future<ZenResult<void>> acknowledge(List<ZenAcknowledgedRecord> saved) => _serialized(() async {
    if (_closed) return ZenResult.err(const ZenStorageError('The store is closed.'));
    final transportData = Map.of(_transportData);
    final unsent = {..._unsent};
    final touched = <int>{};
    for (final item in saved) {
      final ZenStoreKey key;
      try {
        key = ZenStoreKey.parse(item.name);
      } on FormatException {
        continue;
      }
      final record = _records[key];
      if (record == null) continue;
      if (item.transportData case final data?) transportData[key] = data;
      if (sameBytes(encodePayload(record, _names), item.payload)) unsent.remove(item.name);
      touched.add(_shardOf(key));
    }
    try {
      await _persist(_records, transportData, _names, unsent, _transportState, touched);
    } on FileSystemException catch (e, stack) {
      return ZenResult.err(ZenStorageError('Cannot save sync progress: $e', stackTrace: stack));
    }
    _commit(_records, transportData, _names, unsent);
    return const ZenResult.ok(null);
  });

  /// What the transport asked to keep between launches (CloudKit's change token), encrypted with
  /// everything else.
  Uint8List? get transportState => _transportState;

  /// Keeps [state] for the transport.
  Future<ZenResult<void>> saveTransportState(Uint8List? state) => _serialized(() async {
    try {
      await _persist(_records, _transportData, _names, _unsent, state, const {});
    } on FileSystemException catch (e, stack) {
      return ZenResult.err(ZenStorageError('Cannot save sync state: $e', stackTrace: stack));
    }
    _transportState = state;
    return const ZenResult.ok(null);
  });

  /// Forgets everything the transport stored and marks every record unsent, so all of it is sent
  /// again from scratch — after the cloud's copy was reset (a reset iCloud Keychain), or when the
  /// application moves to another transport.
  Future<ZenResult<void>> forgetTransport() => _serialized(() async {
    final everything = {
      for (final key in _records.keys)
        if (!_deviceOnly.contains(key.collection)) key.name,
    };
    try {
      await _persist(_records, const {}, _names, everything, null, {
        for (var shard = 0; shard < _shardCount; shard++) shard,
      });
    } on FileSystemException catch (e, stack) {
      return ZenResult.err(ZenStorageError('Cannot reset sync: $e', stackTrace: stack));
    }
    _transportData.clear();
    _transportState = null;
    _unsent = everything;
    if (everything.isNotEmpty) _unsentChanges.add(everything);
    return const ZenResult.ok(null);
  });

  /// Whether this store was erased everywhere ([eraseEverywhere], or another device did and a
  /// transport brought the news). It then holds no record, refuses every write and merge, and
  /// stays so until its directory is erased and a new store is opened (`ZenStore.erase`).
  bool get erasedEverywhere => _erasedEverywhere;

  /// Fires once, when the store becomes erased everywhere.
  Stream<void> get erasures => _erasures.stream;

  /// Erases the person's data on every device, not only this one (ADR-078 keeps [erase] to this
  /// device's copy).
  ///
  /// Here it removes every record and every unsent change, and marks the store erased, durably:
  /// the mark survives a restart, so a transport that was not done when the app stopped finishes
  /// at the next launch. What reaches the other devices is the transport's: it tells them, each
  /// one erases its copy at its next sync and answers the same way, and it removes what it put in
  /// the shared place (the folder's files, the CloudKit zone). Call the transport's own
  /// `eraseEverywhere` where there is one, so that happens before this returns.
  ///
  /// Idempotent: a store already erased answers success. Nothing here can be undone.
  Future<ZenResult<void>> eraseEverywhere() => _serialized(() async {
    if (_closed) return ZenResult.err(const ZenStorageError('The store is closed.'));
    if (_erasedEverywhere) return const ZenResult.ok(null);
    _erasedEverywhere = true;
    try {
      await _persist(const {}, const {}, _names, const {}, null, {
        for (var shard = 0; shard < _shardCount; shard++) shard,
      });
    } on FileSystemException catch (e, stack) {
      _erasedEverywhere = false;
      return ZenResult.err(ZenStorageError('Cannot erase the store: $e', stackTrace: stack));
    }
    final collections = {for (final record in _records.values) record.collection};
    _commit(const {}, const {}, _names, const {});
    _transportState = null;
    if (collections.isNotEmpty) _changes.add(collections);
    _erasures.add(null);
    return const ZenResult.ok(null);
  });

  static const ZenStorageError _erasedError = ZenStorageError(
    'The store was erased everywhere; nothing can be written to it. Erase its directory and '
    'start a new store.',
  );

  /// Waits for pending writes, then stops accepting new ones.
  Future<void> close() async {
    await _serialized(() async {
      _closed = true;
    });
    await _erasures.close();
    await _changes.close();
    await _unsentChanges.close();
  }

  // ── For ZenCollection ─────────────────────────────────────────────────────────────────────────

  /// The record's state, or null when no device has written it.
  @internal
  ZenRecordState? recordFor(String collection, String id) => _records[ZenStoreKey(collection, id)];

  /// Every record in [collection], deleted ones included, ordered by id.
  @internal
  List<ZenRecordState> recordsIn(String collection) =>
      _records.values.where((record) => record.collection == collection).toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  /// The name [device] goes by, or its id when it never gave one.
  @internal
  String nameOf(String device) => _names[device] ?? device;

  /// Writes [fields] (null for a delete) to the record as this device, once `precondition` — run
  /// against the record as it stands when the write takes its turn — allows it. With [settle], the
  /// write replaces every version in conflict; only a resolution passes it.
  @internal
  Future<ZenResult<R>> write<R>(
    String collection,
    String id,
    ZenResult<(Map<int, Uint8List>?, R)> Function(ZenRecordState? current) precondition, {
    bool settle = false,
  }) => _serialized(() async {
    if (_closed) return ZenResult.err(const ZenStorageError('The store is closed.'));
    if (_erasedEverywhere) return ZenResult.err(_erasedError);
    final key = ZenStoreKey(collection, id);
    final (Map<int, Uint8List>?, R) plan;
    switch (precondition(_records[key])) {
      case ZenSuccess(:final data):
        plan = data;
      case ZenFailure(:final error):
        return ZenResult.err(error);
    }
    final record = _records[key]?.copy() ?? ZenRecordState(collection, id);
    record.write(deviceId, _now(), plan.$1, settle: settle);
    final records = {..._records, key: record};
    final syncs = !_deviceOnly.contains(collection);
    final unsent = {..._unsent, if (syncs) key.name};
    try {
      await _persist(records, _transportData, _names, unsent, _transportState, {_shardOf(key)});
    } on FileSystemException catch (e, stack) {
      return ZenResult.err(ZenStorageError('Cannot write $collection/$id: $e', stackTrace: stack));
    }
    _commit(records, _transportData, _names, unsent);
    _changes.add({collection});
    if (syncs) _unsentChanges.add({key.name});
    return ZenResult.ok(plan.$2);
  });

  /// Saves every write and delete of [batch] as one: when this completes, all of them are on disk,
  /// and if it fails, or the device loses power part way, none of them is — or, once the journal
  /// is saved, all of them, completed the next time the store is opened.
  ///
  /// Nothing is written unless every operation is allowed, with the meaning each has alone: a
  /// delete of a record that is not there fails with a [ZenNotFoundError], a record in conflict
  /// with a [ZenConflictError], an id that cannot travel with a [ZenValidationError]; the same
  /// record twice, or a collection of another store, is a [ZenValidationError] too.
  ///
  /// The batch is atomic on this device only. To a [ZenSyncTransport] it is ordinary per-record
  /// changes, so on another device the records arrive one by one and a screen there can briefly
  /// show part of it; a record in the batch that was edited elsewhere merges or conflicts exactly
  /// as it would have written alone.
  ///
  /// If the files cannot be replaced after the journal is saved — a full disk — the store closes
  /// and answers a [ZenStorageError] saying so, because its memory and its files no longer agree
  /// until the journal is finished by reopening it.
  Future<ZenResult<void>> writeAll(ZenBatch batch) {
    final operations = batch.operations;
    return _serialized(() async {
      if (_closed) return ZenResult.err(const ZenStorageError('The store is closed.'));
      if (_erasedEverywhere) return ZenResult.err(_erasedError);
      final seen = <ZenStoreKey>{};
      final plan = <(ZenStoreKey, Map<int, Uint8List>?)>[];
      for (final operation in operations) {
        if (!identical(operation.store, this)) {
          return ZenResult.err(
            ZenValidationError('${operation.collection}/${operation.id} belongs to another store.'),
          );
        }
        if (ZenCollection.invalidId(operation.id) case final error?) return ZenResult.err(error);
        final key = ZenStoreKey(operation.collection, operation.id);
        if (!seen.add(key)) {
          return ZenResult.err(
            ZenValidationError('${key.collection}/${key.id} is in the batch twice.'),
          );
        }
        final current = _records[key];
        if (current != null && current.isInConflict) {
          return ZenResult.err(
            ZenConflictError(
              '${key.collection}/${key.id} was changed differently on two devices; resolve the '
              'conflict before writing it.',
            ),
          );
        }
        if (operation.isDelete && (current == null || current.isDeleted)) {
          return ZenResult.err(ZenNotFoundError('${key.collection}/${key.id} does not exist.'));
        }
        if (operation.check?.call(current) case final error?) return ZenResult.err(error);
        plan.add((key, operation.fields));
      }
      if (plan.isEmpty) return const ZenResult.ok(null);

      final at = _now();
      final records = {..._records};
      final unsent = {..._unsent};
      final touched = <int>{};
      final collections = <String>{};
      for (final (key, fields) in plan) {
        final record = _records[key]?.copy() ?? ZenRecordState(key.collection, key.id);
        record.write(deviceId, at, fields);
        records[key] = record;
        if (!_deviceOnly.contains(key.collection)) unsent.add(key.name);
        touched.add(_shardOf(key));
        collections.add(key.collection);
      }
      try {
        await _persist(
          records,
          _transportData,
          _names,
          unsent,
          _transportState,
          touched,
          atomic: true,
        );
      } on _JournaledBatchUnfinished catch (e, stack) {
        _closed = true;
        return ZenResult.err(
          ZenStorageError(
            'The batch is saved but could not be written into the store\'s files (${e.cause}). '
            'The store is closed; opening it again finishes the batch.',
            stackTrace: stack,
          ),
        );
      } on FileSystemException catch (e, stack) {
        return ZenResult.err(ZenStorageError('Cannot write the batch: $e', stackTrace: stack));
      }
      _commit(records, _transportData, _names, unsent);
      _changes.add(collections);
      final sent = {
        for (final (key, _) in plan)
          if (!_deviceOnly.contains(key.collection)) key.name,
      };
      if (sent.isNotEmpty) _unsentChanges.add(sent);
      return const ZenResult.ok(null);
    });
  }

  // ── Files ─────────────────────────────────────────────────────────────────────────────────────

  /// Writes the metadata, then each shard in [shards]. In that order: a crash between the two can
  /// leave a record listed as unsent whose change did not reach disk — it is then sent as it
  /// stands, which is harmless — but never a changed record that is not listed, which would never
  /// be sent at all.
  ///
  /// That argument covers one shard. With [atomic] the files are instead saved whole as the
  /// journal first, so that a crash after it, between any two renames, is finished at the next
  /// [open] and a crash before it leaves every file as it was. Throws [FileSystemException] when
  /// nothing was changed, and [_JournaledBatchUnfinished] when the journal is saved but the files
  /// could not all be replaced.
  Future<void> _persist(
    Map<ZenStoreKey, ZenRecordState> records,
    Map<ZenStoreKey, Uint8List> transportData,
    Map<String, String> names,
    Set<String> unsent,
    Uint8List? transportState,
    Set<int> shards, {
    bool atomic = false,
  }) async {
    final meta = utf8.encode(
      jsonEncode({
        'format': zenStoreFormat,
        'device': deviceId,
        'names': names,
        'unsent': unsent.toList()..sort(),
        if (transportState != null) 'transport': base64Encode(transportState),
        if (_erasedEverywhere) 'erased': true,
      }),
    );
    final files = <(String, Uint8List)>[(_metaName, await _cipher.seal(meta, _metaName))];
    for (final shard in shards) {
      final keys = {
        ..._shards[shard],
        ...records.keys.where((key) => _shardOf(key) == shard && !_records.containsKey(key)),
      }.toList()..sort((a, b) => a.name.compareTo(b.name));
      final json = utf8.encode(
        jsonEncode({
          'format': zenStoreFormat,
          'records': [
            for (final key in keys)
              if (records[key] case final record?)
                {
                  ...encodeRecord(record, names),
                  if (transportData[key] case final data?) 's': base64Encode(data),
                },
          ],
        }),
      );
      final name = _shardName(shard);
      files.add((name, await _cipher.seal(json, name)));
    }
    if (!atomic) {
      await _replaceFiles(_directory, files);
      return;
    }
    final journal = utf8.encode(
      jsonEncode({
        'format': zenStoreFormat,
        'files': [
          for (final (name, sealed) in files) {'name': name, 'data': base64Encode(sealed)},
        ],
      }),
    );
    final journalFile = File(_join(_directory.path, _journalName));
    await writeAtomically(journalFile, await _cipher.seal(journal, _journalName));
    try {
      await _replaceFiles(_directory, files, afterEach: _afterFileReplaced);
      await journalFile.delete();
    } on Object catch (e) {
      throw _JournaledBatchUnfinished(e);
    }
  }

  /// Finishes a batch whose journal was saved but whose files were not all replaced — the journal
  /// holds every file as it must end up, so replacing them again is the same as the first time —
  /// then deletes the journal. Throws [FormatException] for a journal that does not decrypt or
  /// does not name only this store's files.
  static Future<void> _finishJournaledBatch(Directory directory, ZenStoreCipher cipher) async {
    final file = File(_join(directory.path, _journalName));
    if (!await file.exists()) return;
    final json = decodeJson(
      await cipher.open(await file.readAsBytes(), _journalName),
      _journalName,
    );
    final files = <(String, Uint8List)>[];
    for (final raw in json['files'] as List<Object?>? ?? const []) {
      if (raw is! Map<String, Object?>) throw const FormatException('$_journalName is malformed');
      final name = raw['name'];
      final data = raw['data'];
      if (name is! String || data is! String || !_journaledName.hasMatch(name)) {
        throw const FormatException('$_journalName names a file that is not the store\'s');
      }
      files.add((name, base64Decode(data)));
    }
    await _replaceFiles(directory, files);
    await file.delete();
  }

  static Future<void> _replaceFiles(
    Directory directory,
    List<(String, Uint8List)> files, {
    Future<void> Function(int replaced, int total)? afterEach,
  }) async {
    for (var i = 0; i < files.length; i++) {
      final (name, bytes) = files[i];
      await writeAtomically(
        File(_join(directory.path, name.replaceAll('/', Platform.pathSeparator))),
        bytes,
      );
      await afterEach?.call(i + 1, files.length);
    }
  }

  void _commit(
    Map<ZenStoreKey, ZenRecordState> records,
    Map<ZenStoreKey, Uint8List> transportData,
    Map<String, String> names,
    Set<String> unsent,
  ) {
    for (final key in records.keys) {
      if (!_records.containsKey(key)) _shards[_shardOf(key)].add(key);
    }
    if (!identical(records, _records)) {
      _records
        ..clear()
        ..addAll(records);
    }
    if (!identical(transportData, _transportData)) {
      _transportData
        ..clear()
        ..addAll(transportData);
    }
    _names = names;
    _unsent = unsent;
  }

  /// Runs [action] after every action queued before it, so two writes never interleave their read
  /// of the current state with each other's replacement of it.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// FNV-1a over the record's name: stable across devices, versions and runs, which a Dart
  /// `hashCode` is not.
  static int _shardOf(ZenStoreKey key) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(key.name)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash % _shardCount;
  }

  static String _shardName(int shard) => 'records/${shard.toRadixString(16).padLeft(2, '0')}.zen';

  static String _shardPath(Directory directory, int shard) =>
      _join(directory.path, _shardName(shard).replaceAll('/', Platform.pathSeparator));

  static Future<String> _deviceId(Directory directory) async {
    final file = File(_join(directory.path, 'device.id'));
    if (await file.exists()) {
      final id = (await file.readAsString()).trim();
      if (!_hexId.hasMatch(id)) throw FormatException('${file.path} does not hold a device id');
      return id;
    }
    final id = _randomHex();
    await writeAtomically(file, id.codeUnits);
    return id;
  }

  static String _randomHex() =>
      List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  static String _join(String directory, String name) => '$directory${Platform.pathSeparator}$name';
}

/// A [ZenStore.writeAll] whose journal is on disk but whose files were not all replaced.
final class _JournaledBatchUnfinished implements Exception {
  final Object cause;

  const _JournaledBatchUnfinished(this.cause);
}
