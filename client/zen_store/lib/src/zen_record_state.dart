import 'dart:typed_data';

import 'package:meta/meta.dart';

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

  /// The authors of the versions in conflict, latest first: who changed a field differently, or
  /// who deleted the record and who edited it without having seen the delete.
  List<String> get conflictAuthors {
    final deletions = [...?fields[existenceField]?.where((version) => version.bytes == null)];
    final versions = <ZenFieldVersion>[
      for (final field in conflictingFields) ...fields[field]!,
      if (isDeleteConflict) ...deletions,
      if (isDeleteConflict)
        for (final entry in fields.entries)
          for (final version in entry.value)
            if (version.bytes != null &&
                deletions.every((deletion) => !version.vector.isCoveredBy(deletion.vector)))
              version,
    ]..sort(_newestFirst);
    return {for (final version in versions) version.author}.toList();
  }

  /// The latest time [author] wrote to this record.
  int lastWriteBy(String author) => fields.values
      .expand((versions) => versions)
      .where((version) => version.author == author)
      .fold(0, (latest, version) => version.atMillis > latest ? version.atMillis : latest);

  /// What [author] wrote to each conflicting field, for showing their side of the conflict.
  Map<int, ZenFieldVersion> versionsBy(String author) => {
    for (final field in conflictingFields)
      field: ?fields[field]!.where((version) => version.author == author).firstOrNull,
  };

  /// Whether [author] is the one who deleted the record.
  bool deletedBy(String author) =>
      fields[existenceField]?.any((version) => version.author == author && version.bytes == null) ??
      false;

  /// Merges [other]'s knowledge of the same record into this one. Returns whether anything changed.
  bool merge(ZenRecordState other) {
    var changed = false;
    for (final entry in other.fields.entries) {
      final merged = mergeVersions([...?fields[entry.key], ...entry.value]);
      if (!_sameVersions(fields[entry.key], merged)) {
        fields[entry.key] = merged;
        changed = true;
      }
    }
    if (_dropDeletedFields()) changed = true;
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

  static int _newestFirst(ZenFieldVersion a, ZenFieldVersion b) {
    final byTime = b.atMillis.compareTo(a.atMillis);
    return byTime != 0 ? byTime : b.author.compareTo(a.author);
  }
}

/// The versions of one field that survive a merge: every version not replaced by another, and,
/// where all survivors hold the same value, that value once — two devices making the same change
/// is not a conflict.
@internal
List<ZenFieldVersion> mergeVersions(List<ZenFieldVersion> versions) {
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
