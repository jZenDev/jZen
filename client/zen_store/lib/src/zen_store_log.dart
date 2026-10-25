import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'zen_record_state.dart';

/// The format this version writes and the newest it can read. A newer number was written by a
/// newer version of the application, and merging it would mean guessing at fields this version
/// does not know, so it is refused instead.
const int zenStoreFormat = 1;

/// A record's address: its collection and its id.
@internal
@immutable
final class ZenStoreKey {
  final String collection;
  final String id;

  const ZenStoreKey(this.collection, this.id);

  /// The record's name everywhere outside this device: `<collection>:<id>`. A collection name has
  /// no colon, so the first one separates the two.
  String get name => '$collection:$id';

  /// Throws [FormatException] for a name that is not `<collection>:<id>`.
  static ZenStoreKey parse(String name) {
    final colon = name.indexOf(':');
    if (colon <= 0 || colon == name.length - 1) {
      throw FormatException('"$name" is not a record name');
    }
    return ZenStoreKey(name.substring(0, colon), name.substring(colon + 1));
  }

  @override
  bool operator ==(Object other) =>
      other is ZenStoreKey && other.collection == collection && other.id == id;

  @override
  int get hashCode => Object.hash(collection, id);
}

/// A record's state as JSON, in one canonical order — fields by number, versions by author and
/// time, vectors and names by device — so two devices holding the same state encode the same
/// bytes, and "did a merge add anything" is a comparison of bytes.
@internal
Map<String, Object?> encodeRecord(ZenRecordState record, Map<String, String> names) {
  final authors = <String>{};
  final fields = <String, Object?>{};
  for (final field in record.fields.keys.toList()..sort()) {
    final versions = record.fields[field]!.toList()
      ..sort((a, b) {
        final byAuthor = a.author.compareTo(b.author);
        return byAuthor != 0 ? byAuthor : a.atMillis.compareTo(b.atMillis);
      });
    fields['$field'] = [
      for (final version in versions)
        {
          'v': {
            for (final device in version.vector.counts.keys.toList()..sort())
              device: version.vector.counts[device],
          },
          'a': version.author,
          't': version.atMillis,
          if (version.bytes != null) 'p': base64Encode(version.bytes!),
        },
    ];
    authors.addAll(versions.map((version) => version.author));
  }
  return {
    'c': record.collection,
    'i': record.id,
    'f': fields,
    'n': {for (final author in authors.toList()..sort()) author: ?names[author]},
  };
}

/// Throws [FormatException] for anything that is not an encoded record. Device names found in it
/// are added to [names].
@internal
ZenRecordState decodeRecord(Object? raw, Map<String, String> names) {
  if (raw is! Map<String, Object?>) throw const FormatException('a record is not an object');
  final collection = _string(raw['c'], 'a record has no collection');
  final id = _string(raw['i'], 'a record has no id');
  final rawFields = raw['f'];
  if (rawFields is! Map<String, Object?>) {
    throw FormatException('record $collection:$id has no fields');
  }
  final record = ZenRecordState(collection, id);
  for (final entry in rawFields.entries) {
    final field = int.tryParse(entry.key);
    final rawVersions = entry.value;
    if (field == null || field < 0 || rawVersions is! List<Object?> || rawVersions.isEmpty) {
      throw FormatException('record $collection:$id has a malformed field "${entry.key}"');
    }
    record.fields[field] = mergeVersions([
      for (final rawVersion in rawVersions) _decodeVersion(rawVersion, '$collection:$id'),
    ]);
  }
  if (raw['n'] case final Map<String, Object?> rawNames) {
    for (final entry in rawNames.entries) {
      if (entry.value case final String name when name.isNotEmpty) names[entry.key] = name;
    }
  }
  return record;
}

/// A record as it travels to another device: its encoded state, UTF-8 JSON with a format number.
@internal
Uint8List encodePayload(ZenRecordState record, Map<String, String> names) =>
    utf8.encode(jsonEncode({'format': zenStoreFormat, 'record': encodeRecord(record, names)}));

/// Throws [FormatException] for a payload this version cannot read, including a newer format.
@internal
ZenRecordState decodePayload(List<int> bytes, Map<String, String> names) {
  final json = decodeJson(bytes, 'a record');
  return decodeRecord(json['record'], names);
}

/// Parses a JSON object carrying `format`, refusing a newer one. Throws [FormatException].
@internal
Map<String, Object?> decodeJson(List<int> bytes, String what) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (e) {
    throw FormatException('$what is not valid JSON: ${e.message}');
  }
  if (json is! Map<String, Object?>) throw FormatException('$what is not a JSON object');
  final format = json['format'];
  if (format is! int) throw FormatException('$what has no format number');
  if (format > zenStoreFormat) {
    throw FormatException(
      '$what is format $format, written by a newer version; this version reads up to '
      '$zenStoreFormat',
    );
  }
  return json;
}

ZenFieldVersion _decodeVersion(Object? raw, String record) {
  if (raw is! Map<String, Object?>) throw FormatException('record $record has a bad version');
  final rawVector = raw['v'];
  final at = raw['t'];
  final payload = raw['p'];
  if (rawVector is! Map<String, Object?> || at is! int || (payload != null && payload is! String)) {
    throw FormatException('record $record has a malformed version');
  }
  final counts = <String, int>{};
  for (final entry in rawVector.entries) {
    final count = entry.value;
    if (count is! int || count < 1) throw FormatException('record $record has a bad vector');
    counts[entry.key] = count;
  }
  return ZenFieldVersion(
    ZenVersionVector(counts),
    _string(raw['a'], 'record $record has a version with no author'),
    at,
    payload == null ? null : base64Decode(payload as String),
  );
}

String _string(Object? value, String problem) {
  if (value is! String || value.isEmpty) throw FormatException(problem);
  return value;
}

/// Writes [bytes] to [target] so that a reader sees the old file or the new one, never half of
/// one: a temporary file beside it, flushed, then renamed over it.
@internal
Future<void> writeAtomically(File target, List<int> bytes) async {
  final name = target.uri.pathSegments.last;
  final temporary = File('${target.parent.path}${Platform.pathSeparator}.$name.tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  await temporary.rename(target.path);
}

@internal
bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
