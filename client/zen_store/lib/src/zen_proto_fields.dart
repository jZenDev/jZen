import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Splits a serialized proto message into its top-level fields, keyed by field number, each the
/// exact bytes that field occupies on the wire (every occurrence of a repeated field, in order).
///
/// This is what lets two devices' edits to *different* fields of one record merge on their own:
/// the store compares and versions each field separately. It works on wire bytes, so it needs no
/// knowledge of the message type, and joining the parts back ([joinFields]) yields a message
/// equal to the original — protobuf defines the concatenation of encodings as their merge.
///
/// Throws a [FormatException] for bytes that are not a proto message, and for groups, which
/// proto3 does not have.
@internal
Map<int, Uint8List> splitFields(Uint8List bytes) {
  final parts = <int, BytesBuilder>{};
  var offset = 0;
  while (offset < bytes.length) {
    final start = offset;
    final (tag, afterTag) = _varint(bytes, offset);
    offset = afterTag;
    final field = tag >> 3;
    if (field == 0) throw const FormatException('field number 0 is not valid');
    switch (tag & 7) {
      case 0:
        offset = _varint(bytes, offset).$2;
      case 1:
        offset += 8;
      case 2:
        final (length, afterLength) = _varint(bytes, offset);
        offset = afterLength + length;
      case 5:
        offset += 4;
      default:
        throw FormatException('wire type ${tag & 7} of field $field is not supported');
    }
    if (offset > bytes.length) throw FormatException('field $field runs past the message');
    parts.putIfAbsent(field, BytesBuilder.new).add(Uint8List.sublistView(bytes, start, offset));
  }
  return {for (final entry in parts.entries) entry.key: entry.value.takeBytes()};
}

/// The message whose fields are [fields], in field-number order.
@internal
Uint8List joinFields(Map<int, Uint8List> fields) {
  final builder = BytesBuilder(copy: false);
  for (final field in fields.keys.toList()..sort()) {
    builder.add(fields[field]!);
  }
  return builder.takeBytes();
}

(int, int) _varint(Uint8List bytes, int offset) {
  var value = 0;
  var shift = 0;
  while (true) {
    if (offset >= bytes.length) throw const FormatException('a varint runs past the message');
    if (shift > 63) throw const FormatException('a varint is longer than 10 bytes');
    final byte = bytes[offset++];
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) return (value, offset);
    shift += 7;
  }
}
