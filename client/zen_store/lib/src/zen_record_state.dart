import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'zen_merge_policy.dart';
import 'zen_proto_fields.dart';

/// The pseudo-field that records whether the record exists. Proto field numbers start at 1, so
/// 0 can never collide with a real field.
@internal
const int existenceField = 0;

/// How much of a record each device has seen: per device, the number of its writes to it.
///
/// Comparing two vectors is what tells an edit that *replaces* another (its author had seen it)
/// from one made *alongside* it (neither author saw the other's). Only the second can be a
/// conflict. Wall-clock time can tell neither, which is why the store never uses it to decide.
@internal
@immutable
final class ZenVersionVector {
  final Map<String, int> counts;

  const ZenVersionVector([this.counts = const {}]);

  /// Whether every write this vector has seen, [other] has seen too.
  bool isCoveredBy(ZenVersionVector other) =>
      counts.entries.every((entry) => (other.counts[entry.key] ?? 0) >= entry.value);

  ZenVersionVector join(ZenVersionVector other) {
    final joined = Map.of(counts);
    other.counts.forEach((device, count) {
      if ((joined[device] ?? 0) < count) joined[device] = count;
    });
    return ZenVersionVector(joined);
  }

  /// This vector advanced by one write on [device].
  ZenVersionVector bump(String device) =>
      ZenVersionVector({...counts, device: (counts[device] ?? 0) + 1});

  @override
  bool operator ==(Object other) =>
      other is ZenVersionVector &&
      other.counts.length == counts.length &&
      counts.entries.every((entry) => other.counts[entry.key] == entry.value);

  @override
  int get hashCode =>
      Object.hashAllUnordered(counts.entries.map((e) => Object.hash(e.key, e.value)));
}

/// One value a field has had: its bytes (null when the field is unset, or for [existenceField]
/// when the record is deleted), the vector of the write that produced it, and who wrote it when.
@internal
@immutable
final class ZenFieldVersion {
  final ZenVersionVector vector;
  final String author;
  final int atMillis;
  final Uint8List? bytes;

  const ZenFieldVersion(this.vector, this.author, this.atMillis, this.bytes);
}

/// A record as one device knows it: for every field, the versions none of which replaces another.
///
/// Usually each field has exactly one. Two mean two devices changed that field without seeing each
/// other's change, to different values — a conflict that only a person may settle. The state is
/// merged as a whole between devices ([merge]); merging is order-free and repeatable, so every
/// device that has read the same logs holds the same state.
@internal
final class ZenRecordState {
  final String collection;
  final String id;
  final Map<int, List<ZenFieldVersion>> fields;

  ZenRecordState(this.collection, this.id, [Map<int, List<ZenFieldVersion>>? fields])
    : fields = fields ?? {};

  /// A copy that a write or a merge can change without touching this one.
  ZenRecordState copy() => ZenRecordState(collection, id, {
    for (final entry in fields.entries) entry.key: List.of(entry.value),
  });

  /// Every write any device has made to this record that this device has seen.
  ZenVersionVector get vector {
    var joined = const ZenVersionVector();
    for (final versions in fields.values) {
      for (final version in versions) {
        joined = joined.join(version.vector);
      }
    }
    return joined;
  }

  ZenFieldVersion? get _existence {
    final versions = fields[existenceField];
    return versions != null && versions.length == 1 ? versions.single : null;
  }

  /// The real fields two devices changed to different values.
  Set<int> get conflictingFields => {
    for (final entry in fields.entries)
      if (entry.key != existenceField && entry.value.length > 1) entry.key,
  };

  /// One device deleted the record while another, not having seen the delete, edited it.
  bool get isDeleteConflict {
    if (fields[existenceField] case final versions? when versions.length > 1) return true;
    final existence = _existence;
    if (existence == null || existence.bytes != null) return false;
    return fields.entries.any(
      (entry) =>
          entry.key != existenceField &&
          entry.value.any((version) => !version.vector.isCoveredBy(existence.vector)),
    );
  }

  bool get isInConflict => isDeleteConflict || conflictingFields.isNotEmpty;

  /// Deleted, and nobody's edit is waiting to bring it back.
  bool get isDeleted => !isInConflict && _existence?.bytes == null;

  /// The record's bytes, with each conflicting field taken from its latest version so that a
  /// record in conflict is still shown, never hidden. Callers that care which version is shown
  /// read the conflict instead; nothing here decides it.
  Uint8List visibleBytes({Map<int, ZenFieldVersion> chosen = const {}}) => joinFields({
    for (final entry in fields.entries)
      if (entry.key != existenceField)
        entry.key: ?(chosen[entry.key] ?? _latest(entry.value)).bytes,
  });

  /// The sides of the conflict, empty when there is none, newest first by the latest disputed
  /// write each stands for — which is not always the order of [ZenRecordSide.atMillis].
  ///
  /// Between them they hold **every** version in dispute: each surviving value of each conflicting
  /// field, each delete, and each edit a delete had not seen. A device has one value side, unless
  /// two versions of a disputed field carry its name — it wrote the field again without having
  /// received the merge that attributed an equal edit to it — in which case it has one side per
  /// value, so none is hidden behind another. A delete is always a side of its own, so a device
  /// that deleted the record while a disputed edit of its own is still held has both.
  ///
  /// The answer depends only on the versions held, never on the order a merge listed them in, so
  /// devices holding the same state answer the same sides.
  List<ZenRecordSide> get conflictSides {
    if (!isInConflict) return const [];
    final deletions = [
      if (isDeleteConflict) ...?fields[existenceField]?.where((version) => version.bytes == null),
    ]..sort(_newestFirst);
    final disputed = {
      for (final field in conflictingFields.toList()..sort())
        field: fields[field]!.toList()..sort(_newestFirst),
    };
    // What puts a device on a value side: its versions of the disputed fields, and its edits a
    // delete had not seen — clearing a field is such an edit, so its null bytes count here, while
    // in the existence field null bytes are the delete itself.
    final edits = <ZenFieldVersion>[
      for (final versions in disputed.values) ...versions,
      if (isDeleteConflict)
        for (final MapEntry(key: field, value: versions) in fields.entries)
          for (final version in versions)
            if ((field != existenceField || version.bytes != null) &&
                deletions.every((deletion) => !version.vector.isCoveredBy(deletion.vector)))
              version,
    ]..sort(_newestFirst);

    final authors = {for (final version in deletions.followedBy(edits)) version.author}.toList()
      ..sort();
    final ranked = <(ZenFieldVersion, ZenRecordSide)>[];
    for (final author in authors) {
      final own = <(ZenFieldVersion, Map<int, ZenFieldVersion>?)>[];
      final authored = edits.where((version) => version.author == author).toList();
      if (authored.isNotEmpty) {
        // This device's distinct values of each disputed field, latest first.
        final values = {
          for (final MapEntry(key: field, value: versions) in disputed.entries)
            field: _distinctValues(versions.where((version) => version.author == author)),
        }..removeWhere((_, versions) => versions.isEmpty);
        final count = values.values.fold(1, (most, v) => v.length > most ? v.length : most);
        for (var i = 0; i < count; i++) {
          // What ranks and dates a side: for the first, the device's latest edit in dispute; for
          // a further one, the latest value no side before it shows. A field with fewer values
          // than there are sides repeats its oldest, so each side is still a whole record.
          final introduced = i == 0
              ? authored
              : ([
                  for (final versions in values.values)
                    if (i < versions.length) versions[i],
                ]..sort(_newestFirst));
          own.add((
            introduced.first,
            {
              for (final MapEntry(key: field, value: versions) in values.entries)
                field: versions[i < versions.length ? i : versions.length - 1],
            },
          ));
        }
      }
      final deletion = deletions.where((version) => version.author == author).firstOrNull;
      if (deletion != null) own.add((deletion, null));
      for (final (rank, chosen) in own) {
        // A device with one side is dated by its last write to the record; with several, each is
        // dated by what sets it apart.
        final at = own.length == 1 ? _lastWriteBy(author) : rank.atMillis;
        ranked.add((rank, ZenRecordSide(author, at, chosen)));
      }
    }
    // Ties keep the order built above (by device, then values before the delete), which `sort`
    // alone would not promise.
    final order = List.generate(ranked.length, (i) => i)
      ..sort((a, b) {
        final byRank = _newestFirst(ranked[a].$1, ranked[b].$1);
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    return [for (final i in order) ranked[i].$2];
  }

  /// The latest time [author] wrote to this record.
  int _lastWriteBy(String author) => fields.values
      .expand((versions) => versions)
      .where((version) => version.author == author)
      .fold(0, (latest, version) => version.atMillis > latest ? version.atMillis : latest);

  /// The first of [versions] to hold each value.
  static List<ZenFieldVersion> _distinctValues(Iterable<ZenFieldVersion> versions) {
    final distinct = <ZenFieldVersion>[];
    for (final version in versions) {
      if (!distinct.any((kept) => _sameBytes(kept.bytes, version.bytes))) distinct.add(version);
    }
    return distinct;
  }

  /// Merges [other]'s knowledge of the same record into this one. Returns whether anything changed.
  ///
  /// A field with a [policies] entry whose sides differ merges to the policy's answer instead of
  /// becoming a conflict.
  bool merge(ZenRecordState other, {Map<int, ZenMergePolicy> policies = const {}}) {
    var changed = false;
    for (final entry in other.fields.entries) {
      final merged = mergeVersions([...?fields[entry.key], ...entry.value], policies[entry.key]);
      if (!_sameVersions(fields[entry.key], merged)) {
        fields[entry.key] = merged;
        changed = true;
      }
    }
    if (_dropDeletedFields()) changed = true;
    return changed;
  }

  /// Applies [policies] to fields already holding concurrent versions, as when a collection starts
  /// declaring a policy for data that is already on disk. Returns whether anything changed.
  bool applyPolicies(Map<int, ZenMergePolicy> policies) {
    var changed = false;
    for (final entry in policies.entries) {
      final versions = fields[entry.key];
      if (versions == null || versions.length < 2) continue;
      final merged = mergeVersions(versions, entry.value);
      if (!_sameVersions(versions, merged)) {
        fields[entry.key] = merged;
        changed = true;
      }
    }
    return changed;
  }

  /// Records one write by [device]: every field in [newFields] that differs from what is shown,
  /// and the record's existence (null [newFields] is a delete). With [settle], every field is
  /// rewritten, which is how a person's resolution replaces all the versions in conflict.
  void write(String device, int atMillis, Map<int, Uint8List>? newFields, {bool settle = false}) {
    final next = vector.bump(device);
    ZenFieldVersion version(Uint8List? bytes) => ZenFieldVersion(next, device, atMillis, bytes);

    final exists = newFields != null;
    if (settle || isDeleted == exists || fields[existenceField] == null) {
      fields[existenceField] = [version(exists ? Uint8List(0) : null)];
    }
    if (!exists) {
      _dropDeletedFields();
      return;
    }
    for (final field in {...fields.keys, ...newFields.keys}..remove(existenceField)) {
      final current = fields[field];
      final bytes = newFields[field];
      final unchanged =
          current != null && current.length == 1 && _sameBytes(current.single.bytes, bytes);
      if (settle || (!unchanged && !(current == null && bytes == null))) {
        fields[field] = [version(bytes)];
      }
    }
  }

  /// A deleted record keeps only its tombstone: field versions the delete had seen can never be
  /// shown again. Not while the delete is in conflict, though — then the fields the delete had
  /// seen are the rest of the edited record, and keeping the edit must keep them too.
  bool _dropDeletedFields() {
    final existence = _existence;
    if (existence == null || existence.bytes != null || isDeleteConflict) return false;
    final before = fields.length;
    fields.removeWhere(
      (field, versions) =>
          field != existenceField &&
          versions.every((version) => version.vector.isCoveredBy(existence.vector)),
    );
    return fields.length != before;
  }

  static ZenFieldVersion _latest(List<ZenFieldVersion> versions) =>
      (versions.toList()..sort(_newestFirst)).first;

  /// A total order over values: the later write, then the device id, then the bytes — so that two
  /// versions one device wrote in the same millisecond are not ordered by how a merge happened to
  /// list them.
  static int _newestFirst(ZenFieldVersion a, ZenFieldVersion b) {
    final byTime = b.atMillis.compareTo(a.atMillis);
    if (byTime != 0) return byTime;
    final byAuthor = b.author.compareTo(a.author);
    return byAuthor != 0 ? byAuthor : compareBytes(b.bytes, a.bytes);
  }
}

/// One side of a record in conflict.
@internal
@immutable
final class ZenRecordSide {
  /// The device whose side this is.
  final String author;

  /// When that device wrote it, by its own clock.
  final int atMillis;

  /// The versions of the disputed fields this side holds, or null when it is a delete.
  final Map<int, ZenFieldVersion>? versions;

  const ZenRecordSide(this.author, this.atMillis, this.versions);
}

/// The versions of one field that survive a merge: every version not replaced by another, and,
/// where all survivors hold the same value, that value once — two devices making the same change
/// is not a conflict. With a [policy], survivors holding different values merge to the policy's
/// answer too, when it can read them.
@internal
List<ZenFieldVersion> mergeVersions(List<ZenFieldVersion> versions, [ZenMergePolicy? policy]) {
  final survivors = <ZenFieldVersion>[];
  for (final candidate in versions) {
    final replaced = versions.any(
      (other) =>
          !identical(other, candidate) &&
          candidate.vector.isCoveredBy(other.vector) &&
          candidate.vector != other.vector,
    );
    if (replaced) continue;
    if (survivors.any((kept) => kept.vector == candidate.vector)) continue;
    survivors.add(candidate);
  }
  if (survivors.length > 1 && survivors.every((v) => _sameBytes(v.bytes, survivors.first.bytes))) {
    final latest = ZenRecordState._latest(survivors);
    final joined = survivors.fold(const ZenVersionVector(), (vv, v) => vv.join(v.vector));
    return [ZenFieldVersion(joined, latest.author, latest.atMillis, latest.bytes)];
  }
  if (policy != null && survivors.length > 1) {
    if (applyMergePolicy(policy, survivors) case final winner?) {
      final joined = survivors.fold(const ZenVersionVector(), (vv, v) => vv.join(v.vector));
      return [ZenFieldVersion(joined, winner.author, winner.atMillis, winner.bytes)];
    }
  }
  return survivors;
}

bool _sameVersions(List<ZenFieldVersion>? a, List<ZenFieldVersion> b) {
  if (a == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].vector != b[i].vector || !_sameBytes(a[i].bytes, b[i].bytes)) return false;
  }
  return true;
}

bool _sameBytes(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
