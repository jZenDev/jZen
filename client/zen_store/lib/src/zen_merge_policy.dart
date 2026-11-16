import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'zen_record_state.dart';

/// How two devices' *different* values of one field merge without asking a person.
///
/// By default any two different values a field was set to on two devices — neither device having
/// seen the other's write — are a `ZenConflict`. That is the right default and the wrong question
/// for a field that records *when* the same thing happened: a budget reset revoked on two devices
/// at two moments, a goal completed on two devices, a reminder read on two devices. Both devices
/// hold the same intent; only their clocks differ, and "which time?" has no answer a person could
/// give. A policy declares that, per field, in `ZenStore.collection(mergePolicies:)`.
///
/// Every policy is a pure function of the **values** involved — never of which write arrived first,
/// which device wrote it, or its wall-clock label. So all devices that have read the same writes
/// hold the same result whatever order they read them in, and a policy can never act as a
/// last-writer-wins shortcut. A policy merges only what it can read: a field it cannot decode, or a
/// side that left the field unset where the policy needs a value, stays a conflict for a person.
enum ZenMergePolicy {
  /// The smaller of two timestamps — the moment the intent first happened. For a field holding a
  /// `google.protobuf.Timestamp` or an integer such as epoch milliseconds. A side that cleared the
  /// field disagrees about the intent itself, so it is a conflict, not a merge.
  earliest,

  /// The larger of two timestamps — the moment the intent last happened. Same field types and same
  /// conflict rule as [earliest].
  latest,

  /// True if any side set a `bool` field to true. Proto3 does not write `false`, so a side that
  /// merely holds the default counts as false.
  or,
}

/// The version that wins among [versions] (concurrent, different values) under [policy], or null
/// when the policy cannot decide — then the versions stay a conflict.
@internal
ZenFieldVersion? applyMergePolicy(ZenMergePolicy policy, List<ZenFieldVersion> versions) {
  final values = <ZenFieldVersion, (int, int)>{};
  for (final version in versions) {
    final value = _value(version.bytes);
    if (value == null && !(policy == ZenMergePolicy.or && version.bytes == null)) return null;
    values[version] = value ?? (0, 0);
  }
  int compare((int, int) a, (int, int) b) =>
      a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2);

  var best = values.entries.first;
  for (final entry in values.entries) {
    final order = compare(entry.value, best.value);
    final better = switch (policy) {
      ZenMergePolicy.earliest => order < 0,
      ZenMergePolicy.latest || ZenMergePolicy.or => order > 0,
    };
    if (better) best = entry;
  }
  // The winning *value* may sit in several versions; pick among them by a rule that reads only the
  // versions, so the choice is the same on every device.
  final winners = [
    for (final entry in values.entries)
      if (compare(entry.value, best.value) == 0) entry.key,
  ];
  return winners.reduce(
    (a, b) => a.atMillis != b.atMillis
        ? (a.atMillis > b.atMillis ? a : b)
        : (a.author.compareTo(b.author) >= 0 ? a : b),
  );
}

/// The comparable value of a singular scalar field's wire bytes: an integer or bool (varint, or
/// fixed-width) as `(value, 0)`, a `google.protobuf.Timestamp` as `(seconds, nanos)`. Null for
/// anything else, including an unset field and a repeated one.
(int, int)? _value(Uint8List? bytes) {
  if (bytes == null) return null;
  try {
    final (tag, afterTag) = _varint(bytes, 0);
    switch (tag & 7) {
      case 0:
        final (value, end) = _varint(bytes, afterTag);
        return end == bytes.length ? (value, 0) : null;
      case 1 || 5:
        final width = (tag & 7) == 1 ? 8 : 4;
        if (afterTag + width != bytes.length) return null;
        var value = 0;
        for (var i = width - 1; i >= 0; i--) {
          value = (value << 8) | bytes[afterTag + i];
        }
        return (value, 0);
      case 2:
        final (length, start) = _varint(bytes, afterTag);
        if (start + length != bytes.length) return null;
        var seconds = 0;
        var nanos = 0;
        var offset = start;
        while (offset < bytes.length) {
          final (innerTag, afterInner) = _varint(bytes, offset);
          if (innerTag & 7 != 0) return null;
          final (value, next) = _varint(bytes, afterInner);
          switch (innerTag >> 3) {
            case 1:
              seconds = value;
            case 2:
              nanos = value;
            default:
              return null;
          }
          offset = next;
        }
        return (seconds, nanos);
    }
  } on FormatException {
    return null;
  }
  return null;
}

(int, int) _varint(Uint8List bytes, int offset) {
  var value = 0;
  var shift = 0;
  while (true) {
    if (offset >= bytes.length || shift > 63) throw const FormatException('bad varint');
    final byte = bytes[offset++];
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) return (value, offset);
    shift += 7;
  }
}
