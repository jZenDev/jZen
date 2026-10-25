import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';

import 'zen_collection.dart';
import 'zen_record_state.dart';
import 'zen_storage_error.dart';
import 'zen_store_cipher.dart';
import 'zen_store_log.dart';
import 'zen_sync_report.dart';
import 'zen_sync_transport.dart';

/// A light application's data: proto messages by collection and id, encrypted on this device,
/// readable offline, and kept in step with the user's other devices by a [ZenSyncTransport].
///
/// **On disk** (the directory passed to [open]): `device.id`, this device's random id; `meta.zen`,
/// the device names, which records wait to be sent, and the transport's state; and the records,
/// sharded by a hash of their name into `records/00.zen` … `records/3f.zen` so a write rewrites
/// one small file, not everything. Every file but `device.id` is AES-256-GCM with the key passed to
/// [open], and rewritten atomically. All records are held in memory; reads are synchronous.
///
/// **Merging** never loses an edit without a person's say: edits to different fields merge,
/// equal edits merge, anything else becomes a `ZenConflict` (see [ZenCollection.conflicts]).
/// ADR-065 explains the design.
final class ZenStore {
  static const int _shardCount = 64;
  static final RegExp _collectionName = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final RegExp _hexId = RegExp(r'^[0-9a-f]{32}$');
  static final Random _random = Random.secure();

  final Directory _directory;
  final ZenStoreCipher _cipher;
  final int Function() _now;

  /// This device's id: how other devices tell its writes apart.
  final String deviceId;

  /// The name this device goes by in another device's conflict ("Alex's iPhone").
  final String deviceName;

  final Map<ZenStoreKey, ZenRecordState> _records;
  final Map<ZenStoreKey, Uint8List> _transportData;
  final List<Set<ZenStoreKey>> _shards;
  Map<String, String> _names;
  Set<String> _unsent;
  Uint8List? _transportState;

  final StreamController<Set<String>> _changes = StreamController<Set<String>>.broadcast();
  final StreamController<Set<String>> _unsentChanges = StreamController<Set<String>>.broadcast();
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  ZenStore._(
    this._directory,
    this._cipher,
    this._now,
    this.deviceId,
    this.deviceName,
    this._records,
    this._transportData,
    this._names,
    this._unsent,
    this._transportState,
  ) : _shards = List.generate(_shardCount, (_) => <ZenStoreKey>{}) {
    for (final key in _records.keys) {
      _shards[_shardOf(key)].add(key);
    }
  }

  /// Opens the store kept in [directory], creating it on first use, encrypted with [key] — 32
  /// random bytes the application keeps in the Keychain (`zen_store_cloudkit`'s
  /// `ZenKeychainStoreKey`), never beside the data.
  ///
  /// [deviceName] is what a person sees in a conflict on another device ("Alex's iPhone").
  ///
  /// Fails with a [ZenStorageError] if a file does not decrypt — the wrong key, or a damaged or
  /// altered file — and writes nothing over it. Opening empty would make the next write replace
  /// the user's data; see [erase] for the deliberate way back.
  ///
  /// [now] supplies wall-clock milliseconds, which only ever label a write for a person.
  static Future<ZenResult<ZenStore>> open(
    Directory directory, {
    required String deviceName,
    required List<int> key,
    int Function()? now,
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
      final names = <String, String>{};
      var unsent = <String>{};
      Uint8List? transportState;
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
          deviceId,
          deviceName,
          records,
          transportData,
          names,
          unsent,
          transportState,
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
  ZenCollection<T> collection<T extends GeneratedMessage>(
    String name,
    T Function(List<int> bytes) decode,
  ) {
    if (!_collectionName.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'a collection name is [a-z][a-z0-9_]{0,63}');
    }
    return ZenCollection.internal(this, name, decode);
  }

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
  Set<String> get unsent => Set.unmodifiable(_unsent);

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
        final current = records[key];
        final merged = current?.copy() ?? theirs;
        if (current == null || merged.merge(theirs)) changed.add(key.collection);
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
    final everything = {for (final key in _records.keys) key.name};
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

  /// Waits for pending writes, then stops accepting new ones.
  Future<void> close() async {
    await _serialized(() async {
      _closed = true;
    });
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
    final unsent = {..._unsent, key.name};
    try {
      await _persist(records, _transportData, _names, unsent, _transportState, {_shardOf(key)});
    } on FileSystemException catch (e, stack) {
      return ZenResult.err(ZenStorageError('Cannot write $collection/$id: $e', stackTrace: stack));
    }
    _commit(records, _transportData, _names, unsent);
    _changes.add({collection});
    _unsentChanges.add({key.name});
    return ZenResult.ok(plan.$2);
  });

  // ── Files ─────────────────────────────────────────────────────────────────────────────────────

  /// Writes the metadata, then each shard in [shards]. In that order: a crash between the two can
  /// leave a record listed as unsent whose change did not reach disk — it is then sent as it
  /// stands, which is harmless — but never a changed record that is not listed, which would never
  /// be sent at all.
  Future<void> _persist(
    Map<ZenStoreKey, ZenRecordState> records,
    Map<ZenStoreKey, Uint8List> transportData,
    Map<String, String> names,
    Set<String> unsent,
    Uint8List? transportState,
    Set<int> shards,
  ) async {
    final meta = utf8.encode(
      jsonEncode({
        'format': zenStoreFormat,
        'device': deviceId,
        'names': names,
        'unsent': unsent.toList()..sort(),
        if (transportState != null) 'transport': base64Encode(transportState),
      }),
    );
    await writeAtomically(
      File(_join(_directory.path, 'meta.zen')),
      await _cipher.seal(meta, 'meta.zen'),
    );
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
      await writeAtomically(File(_shardPath(_directory, shard)), await _cipher.seal(json, name));
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
